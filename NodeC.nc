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
#include "includes/channels.h"
#include "includes/am_types.h"
#include "includes/packet.h"

configuration NodeC {
}
implementation {
    components MainC;
    components Node;
    components new AMReceiverC(AM_PACK) as GeneralReceive;
    //components new FloodingC(AM_FLOODING);
    components new TimerMilliC() as acceptTimerC;
    components new TimerMilliC() as writeTimerC;
    components new TimerMilliC() as timeoutTimerC;
    components new TimerMilliC() as listenTimerC;
    components new TimerMilliC() as tableUpdateTimerC;


    Node -> MainC.Boot;

    Node.Receive -> GeneralReceive;

  //  Node.RecieveRoute -> RecieveRouteC;
  //  Node.RecieveRouteReply -> RecieveRouteReply;

    components new ListC(pack, 64) as packLogsC;
    Node.packLogs -> packLogsC;

    components new SimpleSendC(AM_PACK);
    Node.Sendor -> SimpleSendC;

    components TransportC;
    Node.Transport -> TransportC;

    components new ListC(socket_t, 10) as SocketListC;
    Node.SocketList -> SocketListC;

    components ActiveMessageC;
    Node.AMControl -> ActiveMessageC;

    components CommandHandlerC;
    Node.CommandHandler -> CommandHandlerC;

    components RandomC as Random;
    Node.Random -> Random;

    //components NeighborDiscoveryC;
    //Node.NeighborDiscovery -> NeighborDiscoveryC;

    //components DistanceVectorRoutingC;
    //Node.DistanceVectorRouting -> DistanceVectorRoutingC;

    Node.acceptTimer -> acceptTimerC;
    Node.writeTimer -> writeTimerC;
    Node.timeoutTimer -> timeoutTimerC;
    Node.listenTimer -> listenTimerC;
    Node.tableUpdateTimer -> tableUpdateTimerC;
}
