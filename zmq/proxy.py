# PUB-SUB proxy for rd https://github.com/joshber/rd
# Josh Berson, josh@joshberson.net
# 4/2016

# Clients publish to port 7506, subscribe to port 7507
# On the proxy, XSUB socket listens to 7506, XPUB publishes to 7507

# N.b. re XSUB connecting rather than binding: https://github.com/zeromq/libzmq/issues/897

import zmq

def main():
    context = zmq.Context()

    xsub = context.socket( zmq.XSUB )
    xsub.bind( "tcp://localhost:7506" ) # FIXME: bind or connect?
    xsub.setsockopt( zmq.SUBSCRIBE, "" ) # Receive ALL messages published to this port

    xpub = context.socket( zmq.XPUB )
    xpub.bind( "tcp://*:7507" )

    while True:
        msg = ""
        try:
            # FIXME: NOBLOCK?
            # Receive messages from remote clients (RD instances) and republish them
            msg = xsub.recv_string()
            if msg != "":
                xpub.send_string( msg )

        except zmq.ZMQError as e:
            if e.errno == zmq.ETERM:
                break

if __name__ == '__main__' :
    main()
