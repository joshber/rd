# PUB–SUB proxy for rd
# Josh Berson, josh@joshberson.net
# 4/2016

# Clients publish to port 7506, subscribe to port 7507
# On the proxy, XSUB socket listens to 7506, XPUB publishes to 7507

# Proxy is hosted on 188.226.233.222 (Llama droplet, Amsterdam)

# https://github.com/imatix/zguide/blob/master/examples/Python/espresso.py
# https://stackoverflow.com/questions/21768823/zeromq-mutliple-publishers-and-subscribers-using-xpub-xsub-is-this-a-correct-i
# N.b. re XSUB connecting rather than binding: https://github.com/zeromq/libzmq/issues/897

import zmq

def main():
    context = zmq.Context()

    xsub = context.socket( zmq.XSUB )
    xsub.bind( "tcp://localhost:7506" ) # TODO: bind or connect?

    xpub = context.socket( zmq.XPUB )
    xpub.bind( "tcp://*:7507" )

    while True:
        try:
            signal = xsub.recv()
            if signal != ""
                xpub.send( signal )

        except zmq.ZMQError as e:
            if e.errno == zmq.ETERM:
                break


if __name__ == '__main__' :
    main()
