from __future__ import print_function
import logging
import sys

import gi

gi.require_version('Gst', '1.0')
from gi.repository import GLib, GObject, Gst
import numpy
import cv2
import darknet
import atexit
import threading
from concurrent.futures import ThreadPoolExecutor, Future

logger = logging.getLogger(__name__)


class DarknetProc(object):

    def __init__(self):
        logger.info('Init darknet')
        self.det = darknet.make_detector_demo("cfg/coco.data", "cfg/yolo.cfg", "yolo.weights", .24, .5)
        self._lock = threading.Lock()
        atexit.register(self.destroy)

    def destroy(self):
        with self._lock:
            if self.det is not None:
                darknet.free_detector_demo(self.det)
                self.det = None

    def process_image(self, image):
        with self._lock:
            height, width, depth = image.shape
            bytes_per_line = width * depth
            # Create darknet image from OpenCV image and convert from BGR to RGB
            dimg = darknet.data_to_image(image.ctypes, width, height, depth, bytes_per_line)
            # darknet.rgbgr_image(dimg)
            # Process image with darknet
            darknet.detector_demo_process_image(self.det, dimg)
            # Convert RGB to BGR and copy into original OpenCV image
            darknet.rgbgr_image(dimg)
            darknet.copy_image_into_data(dimg, image.ctypes, width, height, depth, bytes_per_line)
            del dimg
            return image

    def __del__(self):
        self.destroy()


darknet_proc = DarknetProc()


# based on https://stackoverflow.com/questions/22582031/reading-a-h264-rtsp-stream-into-python-and-opencv

class GLibThread(object):

    def __init__(self):
        # Init Gstreamer
        GObject.threads_init()
        Gst.init(None)

        self.thread = threading.Thread(name='GLibThreadLoop', target=self._run_loop)
        self.loop = GLib.MainLoop()
        self.thread.daemon = False
        self.thread.start()
        self.stop_callbacks = []

        atexit.register(self.stop)

    def register_stop_callback(self, cb):
        self.stop_callbacks.append(cb)

    def unregister_stop_callback(self, cb):
        self.stop_callbacks.remove(cb)

    def _run_loop(self):
        try:
            self.loop.run()
        except KeyboardInterrupt:
            self.stop()
            raise

    def join(self, *args, **kwargs):
        self.thread.join(*args, **kwargs)

    def stop(self):
        logger.info('stopping glib loop')
        try:
            for cb in self.stop_callbacks:
                cb()
        finally:
            self.loop.quit()


glib_thread = GLibThread()


class StreamProc(object):
    WEBM_STREAM = "webm"
    JPEG_IMAGE = "jpeg"

    def __init__(self):
        self.in_pipeline = None
        self.out_pipeline = None
        self.appsrc = None
        self.in_src = None
        self.num_frames = 0
        self.framerate_num = 30
        self.framerate_denom = 1
        self.fps = float(self.framerate_num) / float(self.framerate_denom)
        self.out_data_handler = None
        self.fd = None
        self.executor = ThreadPoolExecutor(max_workers=1)
        self._ft_image = None

        glib_thread.register_stop_callback(self.stop)

    def stop(self):
        logger.info("stopping pipelines")
        if self.in_pipeline is not None:
            self.in_pipeline.set_state(Gst.State.NULL)
            self.in_pipeline = None
        if self.out_pipeline is not None:
            self.out_pipeline.set_state(Gst.State.NULL)
            self.out_pipeline = None
        if self._ft_image is not None:
            self._ft_image.cancel()
        glib_thread.unregister_stop_callback(self.stop)

    def __del__(self):
        self.stop()

    def create_out_pipeline(self, width, height):
        self.out_pipeline = Gst.parse_launch("appsrc name=src do-timestamp=1 ! "
                                             "video/x-raw, format=RGB,width={width},height={height}, "
                                             " framerate=(fraction){framerate_num}/{framerate_denom} ! "
                                             "videoconvert ! "
                                             "video/x-raw, format=(string)I420 ! vp8enc ! "
                                             "webmmux streamable=true name=stream ! appsink name=outsink "
                                             .format(framerate_num=self.framerate_num,
                                                     framerate_denom=self.framerate_denom,
                                                     width=width, height=height))
        self.appsrc = self.out_pipeline.get_by_name("src")
        self.appsrc.set_property('emit-signals', True)
        self.appsrc.set_property("format", Gst.Format.TIME)

        # getting the sink by its name set in CLI
        self.out_sink = self.out_pipeline.get_by_name("outsink")

        # setting some important properties of appsnik
        self.out_sink.set_property("max-buffers", 20)  # prevent the app to consume huge part of memory
        self.out_sink.set_property('emit-signals', True)  # tell sink to emit signals
        self.out_sink.set_property('sync', False)  # no sync to make decoding as fast as possible

        self.out_sink.connect('new-sample', self.on_out_buffer)  # connect signal to callable func

        out_bus = self.out_pipeline.get_bus()
        out_bus.add_signal_watch()
        out_bus.connect("message", self.on_out_message)

        # Start
        self.out_pipeline.set_state(Gst.State.PLAYING)

    def on_out_buffer(self, appsink):
        if self.out_data_handler:

            sample = appsink.emit('pull-sample')
            caps = sample.get_caps()
            # print("OUT CAPS", caps.to_string(), file=sys.stderr)
            struct = caps.get_structure(0)
            width = struct.get_int('width')[1]
            height = struct.get_int('height')[1]
            # get the buffer
            buf = sample.get_buffer()
            data = buf.extract_dup(0, buf.get_size())

            if self.fd is None:
                logger.debug("Opened dump.webm")
                self.fd = open('dump.webm', 'wb')
            self.fd.write(data)
            self.fd.flush()

            self.out_data_handler(data)
        return False

    def _process_bufdata_to_jpeg(self, data, width, height):
        arr = numpy.ndarray(
            (height, width, 3),
            buffer=data,
            dtype=numpy.uint8)

        darknet_proc.process_image(arr)
        # cv2.cvtColor(src=arr, dst=arr, code=cv2.COLOR_RGB2BGR)
        ret, jpeg = cv2.imencode('.jpg', arr)
        data = jpeg.tobytes()
        self.out_data_handler(data)

    def on_new_buffer(self, appsink):
        # print('new_buffer')
        sample = appsink.emit('pull-sample')
        caps = sample.get_caps()
        # print("IN CAPS", caps.to_string(), file=sys.stderr)
        struct = caps.get_structure(0)
        width = struct.get_int('width')[1]
        height = struct.get_int('height')[1]

        if self.out_data_handler:
            if self.out_data_handler_mode == self.JPEG_IMAGE:

                if self._ft_image is None or self._ft_image.done():
                    if self._ft_image is not None:
                        exc = self._ft_image.exception()
                        if exc is not None:
                            logger.error('Error while processing image: %s', exc)
                    # print('FT_IMAGE', self._ft_image, file=sys.stderr)
                    # get the buffer
                    buf = sample.get_buffer()
                    data = buf.extract_dup(0, buf.get_size())
                    # print('submit job {}x{}'.format(width, height), file=sys.stderr)
                    self._ft_image = self.executor.submit(self._process_bufdata_to_jpeg, data, width, height)

            elif self.out_data_handler_mode == self.WEBM_STREAM:
                # get the buffer
                buf = sample.get_buffer()
                data = buf.extract_dup(0, buf.get_size())
                arr = numpy.ndarray(
                    (height, width, 3),
                    buffer=data,
                    dtype=numpy.uint8)

                data = arr.tostring()
                duration = (1.0 / self.fps) * Gst.SECOND
                timestamp = self.num_frames * duration
                out_buf = Gst.Buffer.new_allocate(None, len(data), None)
                out_buf.fill(0, data)
                out_buf.duration = duration
                out_buf.dts = out_buf.pts = timestamp

                if not self.appsrc:
                    self.create_out_pipeline(width, height)

                self.appsrc.emit("push-buffer", out_buf)

        self.num_frames += 1

        return False

    def on_message(self, bus, message):
        t = message.type
        logger.debug('Message type %s', t)
        if self.in_pipeline is None:
            return

        if t == Gst.MessageType.STATE_CHANGED:
            # if message.parse_state_changed()[1] == Gst.State.PAUSED:
            decoder = self.in_pipeline.get_by_name("decoder")
            for pad in decoder.srcpads:
                caps = pad.query_caps(None)
                structure_name = caps.to_string()
                logger.debug('Structure name: %s', structure_name)
                struct = caps.get_structure(0)
                if struct:
                    width = struct.get_int('width')
                    height = struct.get_int('height')
                    if width[0] and height[0]:
                        logger.debug("CAPS Width:%s, Height:%s", width[1], height[1])
                        break
                    if structure_name.startswith("video") and len(str(width)) < 6:
                        logger.debug("Width:%d, Height:%d", width, height)
                        # self.player.set_state(Gst.State.NULL)
                        break
        elif t == Gst.MessageType.EOS:
            self.in_pipeline.set_state(Gst.State.NULL)
        elif t == Gst.MessageType.ERROR:
            self.in_pipeline.set_state(Gst.State.NULL)
            err, debug = message.parse_error()
            logger.error("Error: %s %s", err, debug)

    def on_out_message(self, bus, message):
        t = message.type
        logger.debug('Output Message type: %s', t)

        if self.out_pipeline is None:
            return

        if t == Gst.MessageType.EOS:
            self.out_pipeline.set_state(Gst.State.NULL)
        elif t == Gst.MessageType.ERROR:
            self.out_pipeline.set_state(Gst.State.NULL)
            err, debug = message.parse_error()
            logger.error("Output Error: %s %s", err, debug)

    def run(self, out_data_handler, out_data_handler_mode=JPEG_IMAGE):
        self.out_data_handler = out_data_handler
        self.out_data_handler_mode = out_data_handler_mode
        # simplest way to create a pipeline
        self.in_pipeline = Gst.parse_launch("appsrc name=insrc ! queue ! decodebin name=decoder ! videoconvert ! "
                                            "video/x-raw, format=RGB ! queue ! appsink name=sink ")

        self.in_src = self.in_pipeline.get_by_name("insrc")

        # getting the sink by its name set in CLI
        appsink = self.in_pipeline.get_by_name("sink")

        # setting some important properties of appsnik
        appsink.set_property("max-buffers", 20)  # prevent the app to consume huge part of memory
        appsink.set_property('emit-signals', True)  # tell sink to emit signals
        appsink.set_property('sync', False)  # no sync to make decoding as fast as possible

        appsink.connect('new-sample', self.on_new_buffer)  # connect signal to callable func

        bus = self.in_pipeline.get_bus()
        bus.add_signal_watch()
        bus.connect("message", self.on_message)

        self.in_pipeline.set_state(Gst.State.PLAYING)

    def process_data(self, data):
        in_buf = Gst.Buffer.new_allocate(None, len(data), None)
        in_buf.fill(0, data)
        self.in_src.emit("push-buffer", in_buf)


if __name__ == "__main__":
    app = StreamProc()
    app.run()
