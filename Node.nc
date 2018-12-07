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
  bool fired = FALSE;
  bool initialized = FALSE;

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
      call acceptTimer.startPeriodicAt(t0, tI);
      dbg(GENERAL_CHANNEL, "Booted\n");
    }

//t0 milliseconds begins timer and fires every tI interval
  event void acceptTimer.fired(){
    uint32_t t0, tI;
    scanNeighbors();

    t0 = 20000 + call Random.rand32() % 1000;
    tI = 25000 + call Random.rand32() % 10000;

    if(!fired){
      call tableUpdateTimer.startPeriodicAt(t0, tI);
      fired = TRUE;
    }
  }

//initialize timer to update table
  event void tableUpdateTimer.fired(){
    dbg(GENERAL_CHANNEL, "tableUpdateTimer.fired() {\n");
    if(initialized == FALSE){
      initialize();
      initialized = TRUE;
    } else sendTableToNeighbors();
  }

//initialize timer to listen for sockets
  event void listenTimer.fired(){
    socket_store_t sockListen;
    int length;
    dbg(GENERAL_CHANNEL, "listenTimer.fired() {\n");

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

//initialize Timer for writing data
  event void writeTimer.fired(){
    socket_store_t sockWrite;
    dbg(GENERAL_CHANNEL, "listenTimer.fired() {\n");

    if(call Transport.isValidSocket(fd)){
      dbg(GENERAL_CHANNEL, "\t\t\t    -- Socket is valid!!! \n");
      sockWrite = call Transport.getSocket(fd);
    } else dbg(GENERAL_CHANNEL, "\t\t\t    -- Socket is not valid!!! \n");

    if(sockWrite.lastWritten == 0 || sockWrite.lastWritten == SOCKET_BUFFER_SIZE){
      dbg(GENERAL_CHANNEL, "\t\t\t    -- Making data, sending %u bytes\n", transfer);

      //Run stop and wait
      call Transport.stopAndWait(sockWrite, transfer, nodeSeq);
      nodeSeq++;
    }
  }

//initialize time out timer
  event void timeoutTimer.fired(){

    dbg(GENERAL_CHANNEL, "timeoutTimer.fired() -- No ACK received \n");
  }

//Radios on
    event void AMControl.startDone(error_t err) {
        if(err == SUCCESS) {
            dbg(GENERAL_CHANNEL, "Radio On\n");
        } else {
            //Retry until successful
            call AMControl.start();
        }
    }

    event void AMControl.stopDone(error_t err) {}

//Recieve function for pack handling
    event message_t* Receive.receive(message_t* msg, void* payload, uint8_t length) {
        pack* myMsg = (pack*) payload;
        pack* recievedMsg;
        uint8_t nextHop;
        bool alteredRoute = FALSE;

        if(length != sizeof(pack)) {
          //Check if we have seen the message
          if(hasSeen(recievedMsg)){
            dbg(GENERAL_CHANNEL, "\tPackage(%d,%d) has been seen\n", recievedMsg->src, recievedMsg->dest);
            return msg;
          }
          else if(recievedMsg->TTL = 0){
            dbg(GENERAL_CHANNEL, "\tPackage(%d,%d) timed out\n", recievedMsg->src, recievedMsg->dest);
            return msg;
          }
          //Ping msg
          if(recievedMsg->protocol == PROTOCOL_PING && recievedMsg->dest == TOS_NODE_ID){
            dbg(FLOODING_CHANNEL, "\tPackage(%d,%d) Ping Recieved Seq(%d): %s\n", recievedMsg->src, recievedMsg->dest,  recievedMsg->seq, recievedMsg->payload);
            logPacket(&sendPackage);

            //PingReply ^msg
            nodeSeq++;
            makePack(&sendPackage, recievedMsg->dest, recievedMsg->src, MAX_TTL, PROTOCOL_PINGREPLY, nodeSeq, (uint8_t*)recievedMsg->payload, length);
            logPacket(&sendPackage);
            nextHop = findNextHop(recievedMsg->src);
            call Sendor.send(sendPackage, nextHop);
            return msg;
          }
          //PingReply
          else if(recievedMsg->dest == TOS_NODE_ID && recievedMsg->protocol == PROTOCOL_PINGREPLY){
            dbg(FLOODING_CHANNEL, "\tPackage(%d,%d) Ping Reply Recieved: %s\n", recievedMsg->src, recievedMsg->dest, recievedMsg->payload);
            logPacket(&sendPackage);
            return msg;
          }
          //Add Neighbor
          else if(recievedMsg->dest == AM_BROADCAST_ADDR && recievedMsg->protocol == PROTOCOL_PING){
            dbg(GENERAL_CHANNEL, "Neighbor Discovery packet src: %d\n", recievedMsg->src);
            addNeighbor(recievedMsg->src);
            logPacket(recievedMsg);
            return msg;
          }
          //DV table
          else if(recievedMsg->dest == TOS_NODE_ID && recievedMsg->protocol == PROTOCOL_DV){
            dbg(GENERAL_CHANNEL, "Merge Route!!!\n");
            alteredRoute = mergeRoute((uint8_t*)recievedMsg->payload, (uint8_t)recievedMsg->src);
            if(alteredRoute = TRUE){
              sendTableToNeighbors();
            }
            return msg;
          }
          //If packet reaches incorrect dest, relay to neighbors
          else if(recievedMsg->dest != AM_BROADCAST_ADDR && recievedMsg->dest != TOS_NODE_ID){
            dbg(GENERAL_CHANNEL, "Incorrect Destination, Relaying!!!\n");
            recievedMsg->TTL--;
            makePack(&sendPackage, recievedMsg->src, recievedMsg->dest, recievedMsg->TTL, recievedMsg->protocol, recievedMsg->seq, (uint8_t*)recievedMsg->payload, length);
            logPacket(&sendPackage);
            relayToNeighbor(&sendPackage);
            return msg;
          }
          //Recieve a TCP pack
          else if(recievedMsg->dest == TOS_NODE_ID && recievedMsg->protocol == PROTOCOL_TCP){
            dbg(GENERAL_CHANNEL, "Recieved a TCP Pack\n");
            logPacket(&sendPackage);
            call Transport.receive(recievedMsg);
            return msg;
          }
          //TCP pack reaches incorrect dest
          else if(recievedMsg->dest != TOS_NODE_ID && recievedMsg->protocol == PROTOCOL_TCP){
            dbg(GENERAL_CHANNEL, "TCP Pack at Incorrect Destination, Relaying!!!\n");
            recievedMsg->TTL--;
            makePack(&sendPackage, recievedMsg->src, recievedMsg->dest, recievedMsg->TTL, recievedMsg->protocol, recievedMsg->seq, (uint8_t*)recievedMsg->payload, length);
            logPacket(&sendPackage);
            relayToNeighbor(&sendPackage);
            return msg;
          }
          dbg(GENERAL_CHANNEL, "Unexpected Packet Type, Dropping!!!\n");
          return msg;
        }
         dbg(GENERAL_CHANNEL, "\tPackage(%d,%d) is Currrupted", recievedMsg->src, recievedMsg->dest);
         return msg;
    }

//Send ping
    event void CommandHandler.ping(uint16_t destination, uint8_t *payload) {
      nodeSeq++;
      dbg(GENERAL_CHANNEL, "\tPackage(%d,%d) Ping Sent\n", TOS_NODE_ID, destination);
      logPacket(&sendPackage);
      if(initialized = FALSE){
        call Sendor.send(sendPackage, AM_BROADCAST_ADDR);
      } else call Sendor.send(sendPackage, findNextHop(destination));
        //call DistanceVectorRouting.ping(destination, payload);
        //call Flooding.ping(destination, payload);
    }

//Print mote's neighbors
    event void CommandHandler.printNeighbors() {
      int count = 0;
      int i;
      dbg(NEIGHBOR_CHANNEL, "\t%d's Neighbors\n", TOS_NODE_ID);
      for(i = 1; i < NeighborListSize; i++){
        if(NeighborList[i] > 0){
          count++;
        }
      }
      if(count == 0)
            dbg(GENERAL_CHANNEL, "Neighbors List is Empty\n");
    }

//Print the routing table
    event void CommandHandler.printRouteTable() {
      dbg(GENERAL_CHANNEL, "\t~~~~~~~%d's Routing Table~~~~~~~\n", TOS_NODE_ID);
		  dbg(GENERAL_CHANNEL, "\tDest\tCost\tNext Hop:\n");
      for(int i = 1; i <= poolSize; i++){
        dbg(GENERAL_CHANNEL, "\t  %d \t  %d \t    %d \n", routing[i][0], routing[i][1], routing[i][2]);
      }
    }

    event void CommandHandler.printLinkState() {}

    event void CommandHandler.printDistanceVector() {}

    event void CommandHandler.printMessage(uint8_t *payload) {
        dbg(GENERAL_CHANNEL, "%s\n", payload);
    }

//Set server port & address for TCP and ensure bind is successful
    event void CommandHandler.setTestServer(uint8_t port) {
        socket_addr_t requiredPort;
        dbg(GENERAL_CHANNEL, "Initialized Server Port: %d\n", port);

        requiredPort.addr = TOS_NODE_ID;
        requiredPort.port = port;

        if(call Transport.bind(fd, &requiredPort) == SUCCESS){
          dbg(GENERAL_CHANNEL, "Server Bind Was Successful!!!\n");
          call Transport.passNeighborList(&NeighborList);
          //Make sure we are listeing
          if(call Transport.listen(fd) == SUCCESS){
            call listenTimer.startTimer(30000);
          }
        }
    }

//Set client port and address for TCP and ensure bind is successful
    event void CommandHandler.setTestClient(uint16_t dest, uint8_t srcPort, uint8_t destPort, uint8_t transfer) {
        socket_addr_t serverAddr, socketAddr;
        socket_store_t socket;
        error_t check = FAIL;
        fd = call Transport.socket();

        socketAddr.port = srcPort;
        socketAddr.addr = TOS_NODE_ID;

        if(call Transport.bind(fd, &socketAddr) == SUCCESS){
          dbg(GENERAL_CHANNEL, "Client Bind Was Successful!!!\n");
          serverAddr.port = destPort;
          serverAddr.addr = dest;
          call Transport.passNeighborList(&NeighborList);

          if(call Transport.connect(fd, &serverAddr) == SUCCESS){
            dbg(GENERAL_CHANNEL, "Connection Was Successful!!!\n");
            call writeTimer.startTimer(60000)
          } else dbg(GENERAL_CHANNEL, "Connection Was Not Successful!!!\n");
        } else dbg(GENERAL_CHANNEL, "Binding Was Not Successful!!!\n");
    }

//Remake of setTestServer
    event void CommandHandler.setAppServer() {
      socket_addr_t requiredPort;
      uint8_t port = 41;
      dbg(GENERAL_CHANNEL, "Initialized Server Port: %d\n", port);

      fd = call Transport.socket();
      requiredPort.addr = TOS_NODE_ID;
      requiredPort.port = port;

      if(call Transport.bind(fd, &requiredPort) == SUCCESS){
        dbg(GENERAL_CHANNEL, "App Server Bind Was Successful!!!\n");
        call Transport.passNeighborList(&NeighborList);
        //Make sure we are listeing
        if(call Transport.listen(fd) == SUCCESS){
          call listenTimer.startTimer(30000);
        }
      }

    }

//Remake of setTestClient
    event void CommandHandler.setAppClient(uint8_t port) {
      socket_addr_t serverAddr, socketAddr;
      socket_store_t socket;
      error_t check = FAIL;
      fd = call Transport.socket();

      socketAddr.port = srcPort;
      socketAddr.addr = TOS_NODE_ID;
      dbg(GENERAL_CHANNEL, "Set App Client For: %d\n", TOS_NODE_ID);

      if(call Transport.bind(fd, &socketAddr) == SUCCESS){
        dbg(GENERAL_CHANNEL, "App Client Bind Was Successful!!!\n");
        serverAddr.port = 41;
        serverAddr.addr = 1;
        call Transport.passNeighborList(&NeighborList);

        if(call Transport.connect(fd, &serverAddr) == SUCCESS){
          dbg(GENERAL_CHANNEL, "App Client Connection Was Successful!!!\n");
          call writeTimer.startTimer(60000)
        } else dbg(GENERAL_CHANNEL, "Connection Was Not Successful!!!\n");
      } else dbg(GENERAL_CHANNEL, "Binding Was Not Successful!!!\n");
    }

//Close connection once three way handshake is complete
    event void CommandHandler.closeConnection(uint8_t dest, uint8_t srcPort, uint8_t destPort, uint8_t transfer) {
      //Impelement in TCProtocol
      socket_store_t socket;
      //toClose = call Transport.findSocket(dest, srcPort, destPort);
      fd = call Transport.findSocket(srcPort, destPort, dest);
         call Transport.close(fd, nodeSeq++);
    }

//Pack Handling
  void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length){
  Package->src = src;
  Package->dest = dest;
  Package->TTL = TTL;
  Package->seq = seq;
  Package->protocol = protocol;
  memcpy(Package->payload, payload, length);

}

//Logging packets
  void logPacket(pack* payload){
    uint16_t src = payload->src;
    uint16_t seq = payload->seq;
    pack loggedPack;

    //Check if pack log is empty and pop off old key value pair to insert new one
    if(call packLogs.size() == 64){
      call packLogs.popfront();
    }
    makePack(&loggedPack, payload->src, payload->dest, payload->TTL, payload->protocol, payload->seq, (uint8_t*) payload->payload, sizeof(pack));
    call packLogs.pushback(loggedPack);
  }

//Check if packets have been seen
  bool hasSeen(pack* packet){
    pack storedPacks;
    int size;
    size = call packLogs.size();
    //Make sure packLogs is not empty
    if(size > 0){
      //iterate through packLogs to check for previously seen packs
      for(int i = 0; i < size; i++){
        storedPacks = call packLogs.get(i);
        if(storedPacks.seq == packet->seq && storedPacks.src == packet->src){
          return 1;
        }
      }
    } return 0;
  }

//Neighbor Discovery
void addNeighbor(uint8_t Neighbor){
  NeighborList[Neighbor] = MAX_NEIGHBOR_TTL;
}

//Dropping neighborPing
  void reduceNeighborTTL(){
    for(int i = 0; i < NeighborListSize; i++){
      if(NeighborList[i] == 1){
        NeighborList[i] = 0;
        routing[i][1] = 255;
        routing[i][2] = 0;
        nodeSeq++;
        makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, 1, PROTOCOL_PING, nodeSeq, "NeighborSearch", PACKET_MAX_PAYLOAD_SIZE);
        call Sendor.send(sendPackage, (uint8_t) i);
      }
      if(NeighborList[i] > 1){
        NeighborList[i] -= 1;
      }
    }
  }

//Relays msg to neighbors in NeighborList, if empty we forward to everyone within range
  void relayToNeighbor(pack* recievedMsg){
    if(destIsNeighbor(recievedMsg)){
      if(recievedMsg->protocol == PROTOCOL_TCP){
        dbg(GENERAL_CHANNEL, "Relaying TCP Packet(%d) To Destination %d\n", recievedMsg->TTL, findNextHop(recievedMsg->dest));
      }
      call Sendor.send(sendPackage, recievedMsg->msg);
    } else {
      if(recievedMsg->protocol == PROTOCOL_TCP){
        dbg(GENERAL_CHANNEL, "Relaying TCP Packet(%d) To Neighbor %d\n", recievedMsg->TTL, findNextHop(recievedMsg->dest));
        call Sendor.send(sendPackage, findNextHop(recievedMsg->msg));
      }
    }
  }

//Check to see if the dest is a neighbor
bool destIsNeighbor(pack* recievedMsg){
  if(NeighborList[recievedMsg->dest] > 0){
    return 1;
  } else return 0;
}

//search for neighbors by broadcasting a ping with TTL of 1 meaning its a direct neighbor
void scanNeighbors(){
  if(initialized = FALSE){
    nodeSeq++;
    makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, 1, PROTOCOL_PING, nodeSeq, "NeighborSearch", PACKET_MAX_PAYLOAD_SIZE);
    call Sendor.send(sendPackage, AM_BROADCAST_ADDR);
  } else reduceNeighborTTL();
}

//Distance Vector Table
void initialize(){
  dbg(ROUTING_CHANNEL, "Initializing Distance Vector Routing Table!!!\n");

  //Set all nodes in table to MAX_HOP and nextHop to an empty first cell
  for(int i = 1; i < 20; i++){
    routing[i][0] = i;
    routing[i][1] = 255;
    routing[i][2] = 0;
  }
  //Set cost for SELF
  routing[TOS_NODE_ID][0] = TOS_NODE_ID;
  routing[TOS_NODE_ID][1] = 0;
  routing[TOS_NODE_ID][2] = TOS_NODE_ID;

  //set cost to all neighbors
  for(int j = 1; j < NeighborListSize; j++){
    if(NeighborList[j] > 0){
      insert(j, 1, j);
    }
  }
}

//insert data to touples
void insert(uint8_t dest, uint8_t cost, uint8_t nextHop){
  routing[dest][0] = dest;
  routing[dest][1] = cost;
  routing[dest][2] = nextHop;
}

//send DV table to neighbors
void sendTableToNeighbors(){
  for(int i = 1; i < NeighborListSize; i++){
    if(NeighborList[i] > 0){
      //i is the node's ID
      splitHorizon((uint8_t) i);
    }
  }
}

//Merge routes, creating an updated DV table
bool mergeRoute(uint8_t* newRoute, uint8_t src){
  int cost, node, nextHop;
  bool alteredRoute = FALSE;

  //Two loops to iterate through routing[] and newRoute. Save values into made variables.
  for(int i = 0; i < 20; i++){
    for(int j = 0; j < 7; j++){
      node = *(newRoute + (j * 3));
      cost = *(newRoute + (j * 3) + 1);
      nextHop = *(newRoute + (j * 3) + 2);

      if(node == routing[i][0]){
        if((cost + 1) <= routing[i][1]){
          routing[i][0] = node;
          routing[i][1] = cost + 1;
          routing[i][2] = src;

          alteredRoute = TRUE;
        }
      }
    }
  }
  return alteredRoute;
}

//When sending DV table to neighbors, our nextHop is the direct neighbor we are sending this to
  void splitHorizon(uint8_t nextHop){
    uint8_t* poisonTable = NULL;
    uint8_t* startOfPoison;
    //Allocating size on heap but returning pointers
    startOfPoison = malloc(sizeof(routing));
    poisonTable = malloc(sizeof(routing));
    //Copy routing table data onto poisonTable
    memcpy(poisonTable, &routing, sizeof(routing));
    startOfPoison = poisonTable;
    //Insert poison to table (MAX_HOP)
    for(int i = 0; i < 20; i++){
      if(nextHop == i){
        //Poison reverse makes the new path cost infinity
        *(poisonTable + (i * 3) + 1) = 25;
      }
    }
    //payload is too large, so we send in chunks starting from 0 to send first table
    for(int i = 0; i < 20; i++){
      //send the next portion of the table to the next node
      if(i % 7 == 0){
        nodeSeq++;
        makePack(&sendPackage, TOS_NODE_ID, nextHop, 2, PROTOCOL_DV, nodeSeq, poisonTable, sizeof(routing));
        call Sendor.send(sendPackage, nextHop);
      }
      poisonTable += 3;
    }
  }

//Search route table for next Hop
uint8_t findNextHop(uint8_t dest){
  uint8_t nextHop;
  for(int i = 0; i <= poolSize; i++){
    if(routing[i][0] == dest){
      nextHop = routing[i][2];
      return nextHop;
    }
  }
}






/*
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
    } */

}
