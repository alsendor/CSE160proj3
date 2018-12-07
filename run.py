from TestSim import TestSim

def main():
    # Get simulation ready to run.
    s = TestSim()

    # Before we do anything, lets simulate the network off.
    s.runTime(1)

    # Load the the layout of the network.
    s.loadTopo("long_line.topo")

    # Add a noise model to all of the motes.
    s.loadNoise("no_noise.txt")

    # Turn on all of the sensors.
    s.bootAll()

    # Add the main channels. These channels are declared in includes/channels.h
    s.addChannel(s.COMMAND_CHANNEL)
    s.addChannel(s.GENERAL_CHANNEL)
#    s.addChannel(s.HASHMAP_CHANNEL)
#    s.addChannel(s.MAPLIST_CHANNEL)
#    s.addChannel(s.FLOODING_CHANNEL)
#    s.addChannel(s.NEIGHBOR_CHANNEL)
#    s.addChannel(s.ROUTING_CHANNEL)
    s.addChannel(s.TRANSPORT_CHANNEL)

    s.runTime(10)

    # After sending a ping, simulate a little to prevent collision.
    s.newServer(1, 41)
    s.runTime(10)
    s.newClient(2, 1, 10, 41, 10)
    s.runTime(10)
    s.newClient(3, 1, 11, 41, 10)
    s.runTime(10)
    s.newClient(4, 1, 12, 41, 10)
    s.runTime(10)


    s.clientClose(2 ,1 ,10, 41)
    s.runTime(10)

if __name__ == '__main__':
    main()
