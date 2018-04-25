var WebSocketClient = require('websocket').client;

var client = new WebSocketClient();

client.on('connectFailed', function(error) {
    console.log('Connect Error: ' + error.toString());
});

client.on('connect', function(connection) {

    connection.on('message', function(message) {
        if (message.type === 'utf8') {
            console.log("Received: '" + message.utf8Data + "'");
            connection.close();
        }
    });

    if (connection.connected) {
        connection.sendUTF("Hello World!");
    }
});

client.connect('ws://localhost:4000');
