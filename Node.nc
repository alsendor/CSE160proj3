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
//#include "includes/channels.h"
#include "includes/socket.h"

module Node {
    uses interface Boot;

    uses interface SplitControl as AMControl;
    uses interface Receive;
    uses interface CommandHandler;

    //uses interface SimpleSend as Flooding;
    uses interface SimpleSend as Sendor;

    //uses interface Receive as RecieveRoute;
    //uses interface Receive as RecieveRouteReply;
    uses interface Random as Random;

    uses interface Transport;
    uses interface NeighborDiscovery as NeighborDiscovery;
    uses interface DistanceVectorRouting as DistanceVectorRouting;

    uses interface Timer<TMilli> as acceptTimer;
    uses interface Timer<TMilli> as writeTimer;
    uses interface Timer<TMilli> as tableUpdateTimer;
    uses interface Timer<TMilli> as listenTimer;
    uses interface Timer<TMilli> as timeoutTimer;
    uses interface List<pack> as packLogs;
    uses interface List<socket_t> as SocketList;
}

implementation {

  uint8_t MAX_HOP = 18;
  uint8_t MAX_NEIGHBOR_TTL = 20;
  uint8_t NeighborListSize = 19;
  uint8_t NeighborList[19];
  uint8_t routing[255][3];
  uint8_t transfer = 0;
  uint8_t numRoutes = 0;
  uint8_t poolSize = 9;
  uint16_t nodeSeq = 0;

  socket_t fd;
  bool fired = false;
  bool initialized = false;

  pack sendPackage;

//Pack functions
  void initialize();
  void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);
  void insert(uint8_t dest, uint8_t cost, uint8_t nextHop);
  void logPacket(pack* payload);
  bool hasSeen(pack* payload);

//Neighbors functions
  void scanNeighbors();
  void addNeighbor(uint8_t Neighbor);
  bool destIsNeighbor(pack* recievedMsg);
  void relayToNeighbor(pack* recievedMsg);
  void reduceNeighborTTL();
  void sendTableToNeighbors();

//Routing functions
  uint8_t findNextHop(uint8_t dest);
  bool mergeRoute(uint8_t* newRoute, uint8_t src);
  void splitHorizon(uint8_t nextHop);

//Booting event
    event void Boot.booted() {
        uint32_t t0, tI;
        call AMControl.start();
      //call NeighborDiscovery.start();
      //call DistanceVectorRouting.start();

//Create start timer and interval timer
      t0 = 500 + call Random.rand32() % 1000;
      tI = 25000 + call Random.rand32() % 10000;
      call Timer.startPeriodic(t0, tI);
      dbg(GENERAL_CHANNEL, "Booted\n");
    }

//t0 milliseconds begins timer and fires every tI interval
  event void Timer.fired(){
    uint32_t t0, tI;
    scanNeighbors();

    t0 = 20000 + call Random.rand32() % 1000;
    tI = 25000 + call Random.rand32() % 10000;

    if(fired = false){
      call tableUpdateTimer.startPeriodic(t0, tI);
      fired = true;
    }
  }

//initialize timer to update table
  event void tableUpdateTimer.fired(){
    dbg(GENERAL_CHANNEL, "tableUpdateTimer.fired() {\n");
    if(initialized == false){
      initialize();
      initialized = true;
    } else sendTableToNeighbors();
  }

//initialize timer to listen for sockets
  event void listenTimer.fired(){
    dbg(GENERAL_CHANNEL, "listenTimer.fired() {\n");
    socket_store_t sockListen;
    int length;

    fd = call Transport.accept(fd);

    if(fd != (socket_t)NULL){
      //Test for size of socketList 
      if(call SocketList.size() < 10){
        dbg(GENERAL_CHANNEL, "\t-- Saved new fd: %d\n", fd);
        call SocketList.pushback(fd);
      } else dbg(GENERAL_CHANNEL, "\t-- SocketList is full\n");

        sockListen = call Transport.getSocket(fd);
        length = call Transport.read(fd, (uint8_t*)sockListen.rcvdBuff, SOCKET_BUFFER_SIZE);
        dbg(GENERAL_CHANNEL,"\t-- Buffer length: %d\n", length);
    } else dbg(GENERAL_CHANNEL, "\t-- fd is NULL\n");

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
        nb = transfer;
        numToSend = 0;
        call writeTimer.startPeriodic(30000);
    }

    event void CommandHandler.setAppServer() {}

    event void CommandHandler.setAppClient() {}

    event void CommandHandler.closeConnection(uint8_t clientAddress, uint16_t dest, uint8_t srcPort, uint8_t destPort) {
      //Impelement in TCProtocol
      socket_t toClose;
      //toClose = call Transport.findSocket(dest, srcPort, destPort);
      if (toClose != 0)
         call Transport.close(toClose);
    }

    event void acceptTimer.fired() {
      socket_t tempSocket;
      int i, size;
      tempSocket = call Transport.accept(socket);
      if (tempSocket != 0) {
        call SocketList.pushback(tempSocket);
      }

      size = call SocketList.size();
      for (i = 0; i < size; i++) {
        newSocket = call SocketList.get(i);
        nb = call Transport.read(newSocket, &numToSend, 2);

         while (nb != 0) {
            dbg(GENERAL_CHANNEL, "Socket %d received number: %d\n", newSocket, numToSend);
            nb = call Transport.read(newSocket, &numToSend, 2);
         }
      }
    }

    event message_t* RecieveRouteReply.receive(message_t* msg, void* payload, uint8_t length){
       if(length == sizeof(pack)){
         pack* myMsg=(pack*) payload;
         dbg(GENERAL_CHANNEL, "REPLY ARRIVE:%s\n", myMsg->payload);

     }
      return msg;
   }

   event message_t* RecieveRoute.receive(message_t* msg, void* payload, uint8_t length){
       if(length == sizeof(pack)){
         pack* myMsg=(pack*) payload;
         dbg(GENERAL_CHANNEL, "ARRIVE:%s\n\n", myMsg->payload);

     }
      return msg;
   }

    event void writeTimer.fired() {
      if (isNewConnection == 1) {
        while (isNewConnection) {
          bytesWrittenOrRead = call Transport.write(socket, &numToSend, 2);
          if (bytesWrittenOrRead == 2) {
             numToSend++;
          }
          if (numToSend == nb+1) {
             dbg(GENERAL_CHANNEL, "Client done sending number sequence.\n");
             isNewConnection = 0;
          }
          if (bytesWrittenOrRead == 0)
             break;
        }
      }
    }

}
