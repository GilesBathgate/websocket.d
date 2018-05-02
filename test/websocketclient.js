var WebSocketClient = require('websocket').client;

var client = new WebSocketClient();

client.on('connectFailed', function(error) {
    console.log('Connect Error: ' + error.toString());
});

client.on('connect', function(connection) {

    connection.on('message', function(message) {
        if (message.type === 'utf8') {
            console.log("Server: " + message.utf8Data);
            if (message.utf8Data === "Hello World!")
                connection.sendUTF("Goodbye");
            else
                connection.sendUTF("Yes afraid so");
        }
    });

    if (connection.connected) {
        connection.sendUTF("Hello World!");
    }
});

client.connect('ws://localhost:4000');
