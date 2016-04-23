# PUB-SUB client for rd https://github.com/joshber/rd
# Josh Berson, josh@joshberson.net
# 4/2016

# Clients publish to port 7506, subscribe to port 7507
# On the proxy, XSUB socket listens to 7506, XPUB publishes to 7507

# 188.226.233.222 == Digital Ocean droplet Llama, Amsterdam

import sys
import zmq

def main():
    context = zmq.Context()

    pub = context.socket( zmq.PUB )
    pub.connect( "tcp://188.226.233.222:7506" )

    sub = context.socket( zmq.SUB )
    sub.connect( "tcp://188.226.233.222:7507" )
    sub.setsockopt( zmq.SUBSCRIBE, "" ) # Receive ALL messages published on this port

    msg = sys.argv[ 1 ]

    received = ""
    try:
        pub.send_string( msg, flags = zmq.NOBLOCK )
        recieved = sub.recv_string( flags = zmq.NOBLOCK )
    except zmq.ZMQError as e:
        if e.errno == zmq.ETERM:
            return

    # Caller scrapes stdout
    if received != "":
        print received

    pub.close()
    sub.close()
    context.destroy()

if __name__ == '__main__' :
    main()
