/**
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */

#include <Timer.h>
#include "includes/CommandMsg.h"
#include "includes/packet.h"

configuration NodeC {
}
implementation {
    components MainC;
    components Node;
    components new AMReceiverC(AM_PACK) as GeneralReceive;
    components new TimerMilliC() as acceptTimerC;
    components new TimerMilliC() as writeTimerC;

    Node -> MainC.Boot;

    Node.Receive -> GeneralReceive;

    components ActiveMessageC;
    Node.AMControl -> ActiveMessageC;

    components CommandHandlerC;
    Node.CommandHandler -> CommandHandlerC;

    components FloodingC;
    Node.Flooding -> FloodingC;

    components NeighborDiscoveryC;
    Node.NeighborDiscovery -> NeighborDiscoveryC;

    components DistanceVectorRoutingC;
    Node.DistanceVectorRouting -> DistanceVectorRoutingC;

    components SocketListC;
    Node.SocketList -> SocketListC;

    Node.acceptTimer -> acceptTimerC;
    Node.writeTimer -> writeTimerC;
}
