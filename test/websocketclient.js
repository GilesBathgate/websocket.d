var WebSocketClient = require('websocket').client;

var client = new WebSocketClient();

client.on('connectFailed', function(error) {
    console.log('Connect Error: ' + error.toString());
});

client.on('connect', function(connection) {
    console.log('connected');

    if (connection.connected) {
        connection.sendUTF("Hello World!");
    }
});

client.connect('ws://localhost:4000');
