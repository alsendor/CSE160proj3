/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date    2013/09/03
 *
 */
#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/protocol.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"
#include "includes/socket.h"

module Node {
    uses interface Boot;
    uses interface SplitControl as AMControl;
    uses interface Receive;
    uses interface CommandHandler;
    uses interface Flooding;
    uses interface NeighborDiscovery as NeighborDiscovery;
    uses interface DistanceVectorRouting as DistanceVectorRouting;

    uses interface Timer<TMilli> as acceptTimer;
    uses interface Timer<TMilli> as writeTimer;
    uses interface List<socket_t> as SocketList;
}

implementation {

    socket_t socket;
    socket_t newSocket = 0;
    uint8_t isNewConnection = 0;

    event void Boot.booted() {
        call AMControl.start();
        dbg(GENERAL_CHANNEL, "Booted\n");
        call NeighborDiscovery.start();
        call DistanceVectorRouting.start();
    }

    event void AMControl.startDone(error_t err) {
        if(err == SUCCESS) {
            dbg(GENERAL_CHANNEL, "Radio On\n");
        } else {
            //Retry until successful
            call AMControl.start();
        }
    }

    event void AMControl.stopDone(error_t err) {}

    event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len) {
        pack* myMsg = (pack*) payload;
        if(len!=sizeof(pack)) {
                dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
        } else if(myMsg->dest == 0) {
            call NeighborDiscovery.handleNeighbor(myMsg);
        } else if(myMsg->protocol == PROTOCOL_DV) {
            call DistanceVectorRouting.handleDV(myMsg);
        } else {
            call DistanceVectorRouting.routePacket(myMsg);
            //call Flooding.handleFlooding(myMsg);
        }
        return msg;
    }

    event void CommandHandler.ping(uint16_t destination, uint8_t *payload) {
        call DistanceVectorRouting.ping(destination, payload);
        //call Flooding.ping(destination, payload);
    }

    event void CommandHandler.printNeighbors() {
            call NeighborDiscovery.printNeighbors();
    }

    event void CommandHandler.printRouteTable() {
        call DistanceVectorRouting.printRouteTable();
    }

    event void CommandHandler.printLinkState() {}

    event void CommandHandler.printDistanceVector() {}

    event void CommandHandler.printMessage(uint8_t *payload) {
        dbg(GENERAL_CHANNEL, "%s\n", payload);
    }

    event void CommandHandler.setTestServer(uint8_t address, uint8_t port) {
        socket_addr_t requiredPort;
        dbg(GENERAL_CHANNEL, "New server event. \n");

        requiredPort.addr = TOS_NODE_ID;
        requiredPort.port = port;
        socket = call Transport.socket();
        call Transport.listen(socket);

        call acceptTimer.startPeriodic(30000);
    }

    event void CommandHandler.setTestClient(uint16_t dest, uint8_t srcPort, uint8_t destPort, uint8_t transfer) {
        socket_addr_t requiredPort;
        socket_addr_t serverInfo;
        dbg(GENERAL_CHANNEL, "New client event. \n");
        dbg(GENERAL_CHANNEL, "");

        requiredPort.addr = TOS_NODE_ID;
        requiredPort.port = srcPort;
        socket = call Transport.socket();
        call Transport.listen(socket);

        serverInfo.addr = dest;
        serverInfo.port = destPort;
        call Transport.connect(socket, &serverInfo);

        isNewConnection = 1;
        nb = num;
        numToSend = 0;
        call writeTimer.startPeriodic(30000);
    }

    event void CommandHandler.setAppServer() {}

    event void CommandHandler.setAppClient() {}

    event void CommandHandler.closeConnection(uint8_t clientAddress, uint16_t dest, uint8_t srcPort, uint8_t destPort) {
      //Impelement in TCProtocol
      socket_t toClose;
      toClose = call Transport.findSocket(dest, srcPort, destPort);
      if (toClose != 0)
         call Transport.close(toClose);
    }

}
