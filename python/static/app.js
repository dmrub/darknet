'strict'

function alertModal(title, body) {
    // Display error message to the user in a modal
    $('#alert-modal-title').html(title);
    $('#alert-modal-body').html(body);
    $('#alert-modal').modal('show');
}

$(function () {
    var recorder;
    var mediaStream;
    var fileName;
    var connection;
    var urlObject = null;

    var docRoot = new URI(window.location);
    var wsPath = new URI("./ws/video").absoluteTo(docRoot);
    if (wsPath.protocol() === "http")
        wsPath.protocol("ws");
    else if (wsPath.protocol() === "https")
        wsPath.protocol("wss");

    function initWebCam() {
        var config = {video: true, audio: true};
        var userstream;
        navigator.mediaDevices.getUserMedia({
            audio: false,
            video: true
        }).then(function (stream) {
            mediaStream = stream;
            document.getElementById('video-in').setAttribute('src', window.URL.createObjectURL(mediaStream));
            var options;
            if (MediaRecorder.isTypeSupported('video/webm;codecs=vp9')) {
              options = {mimeType: 'video/webm; codecs=vp9'};
            } else if (MediaRecorder.isTypeSupported('video/webm;codecs=vp8')) {
               options = {mimeType: 'video/webm; codecs=vp8'};
            } else {
               alertModal('Media Error', 'Media format WebM and vp8 / vp9 codecs are not supported');
               return;
            }

            try {
                recorder = new MediaRecorder(mediaStream, options);
            } catch (err) {
                console.log(err);
                alertModal('Media Error', 'Could not open webcam: '+err.name+' '+err);
            }

            recorder.ondataavailable = function (event) {
                var reader = new FileReader();
                reader.readAsArrayBuffer(event.data);
                reader.onloadend = function (event) {
                    if (connection.readyState === 1 /*OPEN*/ && reader.result.byteLength > 0) {
                        connection.send(reader.result);
                    }
                };
            };

            recorder.onerror = function(event) {
                var error = event.error;

                switch (error.name) {
                    case 'InvalidStateError':
                        alertModal('Invalid Media State Error', "You can't record the video right " +
                            "now. Try again later. Error: "+error);
                        break;
                    case 'SecurityError':
                        alertModal('Media Security Error', "Recording the specified source " +
                            "is not allowed due to security " +
                            "restrictions. Error: "+error);
                        break;
                    default:
                        alertModal('Media Error', "A problem occurred while trying " +
                            "to record the video. Error: "+error);
                        break;
                }
            };
        }).catch(function (err) {
            alertModal('Media Error: '+err.name, 'Could not open webcam'+(err.message ? ': '+err.message : ''));
        });
    }

    function initConnection() {
        connection = new WebSocket(wsPath.toString());
        connection.binaryType = 'arraybuffer';

        connection.addEventListener('message', function (event) {
            var image = document.getElementById('image');
            if (!image.complete) {
                console.log("Drop image");
                return;
            }
            var arrayBuffer = event.data;
            var bytes = new Uint8Array(arrayBuffer);

            var blob = new Blob([arrayBuffer]);
            //try {
            //    image.srcObject = blob;
            //} catch (error) {
                if (urlObject) {
                    URL.revokeObjectURL(urlObject);
                }
                urlObject = URL.createObjectURL(blob);

                image.src = urlObject;
            //}

            //image.src = 'data:image/jpeg;base64,'+encode(bytes);
        });

        connection.addEventListener('error', function (err) {
            alertModal('Connection Error', 'Connection error: '+err.type+' '+err);
        });

        connection.addEventListener('close', function (event) {
            if (recorder.state === 'recording')
                recorder.stop();
        });
    }

    function onConnectedHandler() {
        connection.removeEventListener('open', onConnectedHandler);
        startRecording();
    }

    function startRecording() {
        if (recorder.state === 'recording')
            return;
        if (connection) {
            if (connection.readyState === 1 /*OPEN*/) {
                recorder.start(100/* ms chunk */);
            } else if (connection.readyState === 0 /*CONNECTING*/) {
                connection.addEventListener('open', onConnectedHandler);
            } else {
                initConnection();
                connection.addEventListener('open', onConnectedHandler);
            }
        } else {
            initConnection();
            connection.addEventListener('open', onConnectedHandler);
        }
    }

    function stopRecording() {
        if (recorder.state === 'recording') {
            recorder.stop();
        }
        connection.close();
    }

    var startButton = document.getElementById('record');
    startButton.addEventListener('click', function (e) {
        startRecording();
    });

    var stopButton = document.getElementById('stop');
    stopButton.addEventListener('click', function (e) {
        stopRecording();
    });

    initWebCam();
    initConnection();

    // From https://stackoverflow.com/questions/11089732/display-image-from-blob-using-javascript-and-websockets
    // public method for encoding an Uint8Array to base64
    function encode(input) {
        var keyStr = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
        var output = "";
        var chr1, chr2, chr3, enc1, enc2, enc3, enc4;
        var i = 0;

        while (i < input.length) {
            chr1 = input[i++];
            chr2 = i < input.length ? input[i++] : Number.NaN; // Not sure if the index
            chr3 = i < input.length ? input[i++] : Number.NaN; // checks are needed here

            enc1 = chr1 >> 2;
            enc2 = ((chr1 & 3) << 4) | (chr2 >> 4);
            enc3 = ((chr2 & 15) << 2) | (chr3 >> 6);
            enc4 = chr3 & 63;

            if (isNaN(chr2)) {
                enc3 = enc4 = 64;
            } else if (isNaN(chr3)) {
                enc4 = 64;
            }
            output += keyStr.charAt(enc1) + keyStr.charAt(enc2) +
                keyStr.charAt(enc3) + keyStr.charAt(enc4);
        }
        return output;
    }

});
