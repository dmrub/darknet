from ctypes import *
import math
import random
import sys

def sample(probs):
    s = sum(probs)
    probs = [a/s for a in probs]
    r = random.uniform(0, 1)
    for i in range(len(probs)):
        r = r - probs[i]
        if r <= 0:
            return i
    return len(probs)-1

def c_array(ctype, values):
    arr = (ctype*len(values))()
    arr[:] = values
    return arr

class NETWORK(Structure):
    pass

class LAYER(Structure):
    pass

class DETECTOR_DEMO(Structure):
    pass

class BOX(Structure):
    _fields_ = [("x", c_float),
                ("y", c_float),
                ("w", c_float),
                ("h", c_float)]

class IMAGE(Structure):
    _fields_ = [("w", c_int),
                ("h", c_int),
                ("c", c_int),
                ("data", POINTER(c_float))]

class METADATA(Structure):
    _fields_ = [("classes", c_int),
                ("names", POINTER(c_char_p))]

    

#lib = CDLL("/home/pjreddie/documents/darknet/libdarknet.so", RTLD_GLOBAL)
lib = CDLL("libdarknet.so", RTLD_GLOBAL)
lib.network_width.argtypes = [c_void_p]
lib.network_width.restype = c_int
lib.network_height.argtypes = [c_void_p]
lib.network_height.restype = c_int

predict = lib.network_predict
predict.argtypes = [c_void_p, POINTER(c_float)]
predict.restype = POINTER(c_float)

set_gpu = lib.cuda_set_device
set_gpu.argtypes = [c_int]

make_image = lib.make_image
make_image.argtypes = [c_int, c_int, c_int]
make_image.restype = IMAGE

data_to_image = lib.data_to_image
data_to_image.argtypes = (
            c_void_p, # imagedata
            c_int,    # width
            c_int,    # height
            c_int,    # bytes_per_pixel
            c_int)    # bytes_per_line
data_to_image.restype = IMAGE

data_into_image = lib.data_into_image
data_into_image.argtypes = (
            c_void_p, # imagedata
            c_int,    # width
            c_int,    # height
            c_int,    # bytes_per_pixel
            c_int,    # bytes_per_line
            IMAGE)           # image
data_into_image.restype = None

copy_image_into_data = lib.copy_image_into_data
copy_image_into_data.argtypes = (
            IMAGE,    # image
            c_void_p, # imagedata
            c_int,    # width
            c_int,    # height
            c_int,    # bytes_per_pixel
            c_int     # bytes_per_line
            )
copy_image_into_data.restype = None


save_image = lib.save_image
save_image.argtypes = (
            IMAGE,   # image
            c_char_p # name
            )
save_image.restype = None

show_image = lib.show_image
show_image.argtypes = (
            IMAGE,   # image
            c_char_p # name
            )
show_image.restype = None

make_boxes = lib.make_boxes
make_boxes.argtypes = [c_void_p]
make_boxes.restype = POINTER(BOX)

free_boxes = lib.free_boxes
free_boxes.argtypes = [POINTER(BOX)]
free_boxes.restype = None

free_ptr = lib.free_ptr
free_ptr.argtypes = [c_void_p]
free_ptr.restype = None

free_ptrs = lib.free_ptrs
free_ptrs.argtypes = [POINTER(c_void_p), c_int]

num_boxes = lib.num_boxes
num_boxes.argtypes = [c_void_p]
num_boxes.restype = c_int

make_probs = lib.make_probs
make_probs.argtypes = [c_void_p]
make_probs.restype = POINTER(POINTER(c_float))

detect = lib.network_predict
detect.argtypes = [c_void_p, IMAGE, c_float, c_float, c_float, POINTER(BOX), POINTER(POINTER(c_float))]

reset_rnn = lib.reset_rnn
reset_rnn.argtypes = [c_void_p]

load_net = lib.load_network
load_net.argtypes = [c_char_p, c_char_p, c_int]
load_net.restype = POINTER(NETWORK)

free_net = lib.free_network
free_net.argtypes = [c_void_p]
free_net.restype = None

free_image = lib.free_image
free_image.argtypes = [IMAGE]

letterbox_image = lib.letterbox_image
letterbox_image.argtypes = [IMAGE, c_int, c_int]
letterbox_image.restype = IMAGE

load_meta = lib.get_metadata
lib.get_metadata.argtypes = [c_char_p]
lib.get_metadata.restype = METADATA

load_image = lib.load_image_color
load_image.argtypes = [c_char_p, c_int, c_int]
load_image.restype = IMAGE

rgbgr_image = lib.rgbgr_image
rgbgr_image.argtypes = [IMAGE]
rgbgr_image.restype = None

predict_image = lib.network_predict_image
predict_image.argtypes = [c_void_p, IMAGE]
predict_image.restype = POINTER(c_float)

network_detect = lib.network_detect
network_detect.argtypes = [POINTER(NETWORK), IMAGE, c_float, c_float, c_float, POINTER(BOX), POINTER(POINTER(c_float))]

get_network_n = lib.get_network_n
get_network_n.argtypes = [POINTER(NETWORK)]
get_network_n.restype = c_int

get_network_layer = lib.get_network_layer
get_network_layer.argtypes = [POINTER(NETWORK), c_int]
get_network_layer.restype = POINTER(LAYER)

get_layer_h = lib.get_layer_h
get_layer_h.argtypes = [POINTER(LAYER)]
get_layer_h.restype = c_int

get_layer_w = lib.get_layer_w
get_layer_w.argtypes = [POINTER(LAYER)]
get_layer_w.restype = c_int

get_layer_n = lib.get_layer_n
get_layer_n.argtypes = [POINTER(LAYER)]
get_layer_n.restype = c_int

load_alphabet = lib.load_alphabet
load_alphabet.restype = POINTER(POINTER(IMAGE))

free_alphabet = lib.free_alphabet
free_alphabet.argtypes = [POINTER(POINTER(IMAGE))]

draw_detections = lib.draw_detections
draw_detections.argtypes = [IMAGE, c_int, c_float, POINTER(BOX), POINTER(POINTER(c_float)), POINTER(POINTER(c_float)), POINTER(c_char_p), POINTER(POINTER(IMAGE)), c_int]

make_detector_demo = lib.make_detector_demo
make_detector_demo.argtypes = [c_char_p, c_char_p, c_char_p, c_float, c_float]
make_detector_demo.restype = POINTER(DETECTOR_DEMO)

free_detector_demo = lib.free_detector_demo
free_detector_demo.argtypes = [POINTER(DETECTOR_DEMO)]
free_detector_demo.restype = None

detector_demo_process_file = lib.detector_demo_process_file
detector_demo_process_file.argtypes = [POINTER(DETECTOR_DEMO), c_char_p, c_char_p]
detector_demo_process_file.restype = None

detector_demo_process_image = lib.detector_demo_process_image
detector_demo_process_image.argtypes = [POINTER(DETECTOR_DEMO), IMAGE]
detector_demo_process_image.restype = None


def classify(net, meta, im):
    out = predict_image(net, im)
    res = []
    for i in range(meta.classes):
        res.append((meta.names[i], out[i]))
    res = sorted(res, key=lambda x: -x[1])
    return res

def detect(net, meta, image, thresh=.5, hier_thresh=.5, nms=.45):
    alphabet = load_alphabet()
    im = load_image(image, 0, 0)
    boxes = make_boxes(net)
    probs = make_probs(net)
    num =   num_boxes(net)

    l = get_network_layer(net, get_network_n(net)-1)

    lw = get_layer_w(l)
    lh = get_layer_h(l)
    ln = get_layer_n(l)
    masks = None
    network_detect(net, im, thresh, hier_thresh, nms, boxes, probs)
    res = []
    for j in range(num):
        for i in range(meta.classes):
            if probs[j][i] > 0:
                res.append((meta.names[i], probs[j][i], (boxes[j].x, boxes[j].y, boxes[j].w, boxes[j].h)))
    res = sorted(res, key=lambda x: -x[1])
    #draw_detections(im, lw*lh*ln, thresh, boxes, probs, masks, names, alphabet, l.classes);
    free_alphabet(alphabet)
    free_boxes(boxes)
    free_image(im)
    free_ptrs(cast(probs, POINTER(c_void_p)), num)
    return res

if __name__ == "__main__":
    #net = load_net("cfg/densenet201.cfg", "/home/pjreddie/trained/densenet201.weights", 0)
    #im = load_image("data/wolf.jpg", 0, 0)
    #meta = load_meta("cfg/imagenet1k.data")
    #r = classify(net, meta, im)
    #print r[:10]
    #net = load_net("cfg/tiny-yolo.cfg", "tiny-yolo.weights", 0)
    #meta = load_meta("cfg/coco.data")
    #r = detect(net, meta, "data/dog.jpg")
    #free_net(net)
    #print r
    import os
    import os.path
    det = make_detector_demo("cfg/coco.data", "cfg/yolo.cfg", "yolo.weights", .24, .5)
    out_dir = "out"
    if not os.path.exists(out_dir):
        os.makedirs(out_dir)
    for dirname, dirnames, filenames in os.walk('images'):
        del dirnames[:]
        for filename in filenames:
            if filename.endswith('.jpeg') or filename.endswith('.jpg'):
                infile = os.path.join(dirname, filename)
                outfile = os.path.join(out_dir, os.path.basename(filename))
                detector_demo_process_file(det, infile, outfile)
    #detector_demo_process_file(det, "images/image-0001779.jpeg", None)
    free_detector_demo(det)
