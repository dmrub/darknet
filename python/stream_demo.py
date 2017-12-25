#!/usr/bin/env python
from __future__ import print_function

import logging

LOG_FORMAT = '%(asctime)s %(levelname)s %(pathname)s:%(lineno)s: %(message)s'
logging.basicConfig(format=LOG_FORMAT, level=logging.DEBUG)

import os
import os.path
import signal
import sys

import tornado
import tornado.ioloop
import tornado.options
import tornado.web
import tornado.websocket
from tornado.options import define, options

from streamproc import StreamProc, glib_thread


def signal_term_handler(signal, frame):
    print('Got signal {}, exiting'.format(signal), file=sys.stderr)
    glib_thread.stop()
    sys.exit(0)


signal.signal(signal.SIGTERM, signal_term_handler)
signal.signal(signal.SIGINT, signal_term_handler)

define("port", default=8888, help="run on the given port", type=int)

cl = []


class VideoWebSocketHandler(tornado.websocket.WebSocketHandler):
    def __init__(self, application, request, **kwargs):
        super(VideoWebSocketHandler, self).__init__(application, request, **kwargs)
        self._video_fname = None
        self._conn = None
        self._process = None
        self.stream_proc = None

    def close_video(self):
        if self.stream_proc:
            self.stream_proc.stop()
            self.stream_proc = None

    def check_origin(self, origin):
        return True

    def open(self):
        print('websocket {} opened'.format(self))
        if self not in cl:
            cl.append(self)

        self.close_video()
        self.stream_proc = StreamProc()
        self.stream_proc.run(self.on_out_data)

    def on_out_data(self, data):
        if data:
            print("send data back len={}".format(len(data)))
            try:
                self.write_message(data, binary=True)
            except tornado.websocket.WebSocketError as e:
                logging.exception('Cannot send data back')
                self.close_video()

    def on_message(self, message):
        # print('on_message type {} size {}'.format(type(message), len(message)))
        self.stream_proc.process_data(message)
        # if not self._writer.write_message(message):
        #    print('No connection')
        #    # self.write_message(u"You said: " + message)

    def on_close(self):
        print('websocket {} closed'.format(self))
        if self in cl:
            cl.remove(self)
        self.close_video()


class Application(tornado.web.Application):
    def __init__(self):
        root_dir = os.path.dirname(__file__)
        static_dir = os.path.join(root_dir, 'static')
        handlers = [
            (r'/ws/video', VideoWebSocketHandler),
            (r'/(favicon.ico)', tornado.web.StaticFileHandler, {'path': static_dir}),
            (r'/(.*)', tornado.web.StaticFileHandler, {'path': static_dir, 'default_filename': 'index.html'}),
        ]
        settings = dict(
            cookie_secret=os.urandom(24),
            template_path=os.path.join(root_dir, "templates"),
            static_path=os.path.join(root_dir, "static"),
            xsrf_cookies=True,
        )
        super(Application, self).__init__(handlers, **settings)


def main():

    tornado.options.parse_command_line()
    logging.info('Run on port %i', options.port)
    app = Application()
    app.listen(options.port)

    loop = tornado.ioloop.IOLoop.current()

    def stop_cb():
        logging.info('Stopping IOLoop')
        loop.stop()

    glib_thread.register_stop_callback(stop_cb)
    loop.start()


if __name__ == '__main__':
    main()
