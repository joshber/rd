// ZMQ test

// https://www.digitalocean.com/community/tutorials/how-to-work-with-the-zeromq-messaging-library
/*
Do all the server-side stuff in Python!

Create a "server.py" using nano (nano server.py) and paste the below self-explanatory contents.

import zmq

# ZeroMQ Context
context = zmq.Context()

# Define the socket using the "Context"
sock = context.socket(zmq.REP)
sock.bind("tcp://127.0.0.1:5678")

# Run a simple "Echo" server
while True:
    message = sock.recv()
    sock.send("Echo: " + message)
    print "Echo: " + message

    */

import org.zeromq.ZMQ;

ZMQ.Context zContext;
ZMQ.Socket zPub;
ZMQ.Socket zSub;
final String proxyIP = "188.226.233.222";
    // Digital Ocean droplet Llama (Amsterdam)
    // https://cloud.digitalocean.com/droplets/1559653

// TCP ports to connect PUB and SUB sockets to the proxy
final String toXSUB = "7506";
final String fromXPUB = "7507";

//
// Set up our network topology!
// Each instance gets a PUB and a SUB that connect to a proxy
// On the proxy, corresponding XSUB and XPUB sockets bind to *:7506 and *:7507 respectively

void setup() {
  zContext = ZMQ.context( 1 );
  zPub = zContext.socket( ZMQ.PUB );
  zSub = zContext.socket( ZMQ.SUB );
  zPub.connect( "tcp://" + proxyIP + ":" + toXSUB );
  zSub.connect( "tcp://" + proxyIP + ":" + fromXPUB );


}
