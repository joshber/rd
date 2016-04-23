#! /usr/local/bin/python

# PUB–SUB client for rd
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
    # sys.argv[1] should contain the argument
    # key question is: How to make sure signaling does not turn into an IIR --
    # i.e., instance 0 could broadcast, and other instances could broadcast their response impulses ...
    # maybe an instance only broadcasts impulses generated directly by sound?

# FIXME FOR CLIENT subscriber.setsockopt(zmq.SUBSCRIBE, b"A") on subscriber side ... just preface everything with RD
# sub.recv( flags = zmq.NOBLOCK ) https://pyzmq.readthedocs.org/en/latest/api/zmq.html

# Read signal from command line

# send in byte format, pub.send( b"..." )
