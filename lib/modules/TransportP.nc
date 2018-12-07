#include "../../includes/packet.h"
#include "../../includes/socket.h"
#include "../../includes/TCPpack.h"

/**
 * The Transport interface handles sockets and is a layer of abstraction
 * above TCP. This will be used by the application layer to set up TCP
 * packets. Internally the system will be handling syn/ack/data/fin
 * Transport packets.
 *
 * @project
 *   Transmission Control Protocol
 * @author
 *      Alex Beltran - abeltran2@ucmerced.edu
 * @date
 *   2013/11/12
 */

 module TransportP {
     provides interface Transport;
     uses interface Random as Random;
     uses interface SimpleSend as Sendor;
     uses interface Hashmap<socket_store_t> as sockets;
     uses interface Timer<TMilli> as timeoutTimer;
     uses interface Timer<TMilli> as ackTimer;
 }

implementation {
  uint16_t RTT = 12000;
  uint16_t fdKeys = 0; //number of fdKeys we currently have
  uint8_t numConnected = 0; //number of connected sockets
  uint16_t tcpSeq = 0;
  uint16_t* IPseq = 0;
  uint8_t NeighborList[19];
  uint8_t transfer;
  uint8_t dataSent = 0;
  uint8_t firstNeighbor = 0;
  bool send = TRUE;
  pack sendMessage;

//timer for ACK
  event void ackTimer.fired() {
		TCPpack* payload;
		payload = (TCPpack*)sendMessage.payload;
		dbg(GENERAL_CHANNEL, "\n\tAck %u timed out! Resending!!!\n", payload->seq);
		call Sendor.send(sendMessage, firstNeighbor);
	}

//TCPpack timeout timer
event void timeoutTimer.fired() {
		TCPpack* payload;
		payload = (TCPpack*)sendMessage.payload;
		dbg(GENERAL_CHANNEL, "\n\tPacket %u timed out! Resending to %d\n", tcpSeq, firstNeighbor);
		call Sendor.send(sendMessage, firstNeighbor);
		//call Transport.send(call Transport.findSocket(payload->srcPort,payload->destPort, sendMessage.dest), sendMessage);
		if(datasent != transfer)
			call timeoutTimer.startOneShot(12000);
	}

//Passing the sequence number
command void Transport.passSeq(uint16_t* seq) {
		IPseq = seq;
	}
//Passng the neighbor list
  command void Transport.passNeighborsList(uint8_t* neighbors[]) {
    int i;
    dbg(GENERAL_CHANNEL, "Passing Neighbor List\n");
  		memcpy(NeighborList, (void*)neighbors, sizeof(neighbors));
      //iterate through neighborlist adding in all neighbors
  		for(i = 1; i < 20; i++) {
  			if(NeighborList[i] > 0) {
  				dbg(GENERAL_CHANNEL, "%d's Neighbor is: %d\n", TOS_NODE_ID, i);
  				firstNeighbor = i;
  			}
  		}
  		dbg(GENERAL_CHANNEL, "firstNeighbor: %d\n", firstNeighbor);
  	}

//Create the makepack
  command void Transport.makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length) {
		TCPpack* tcpp = (TCPpack*) payload;

		Package->src = src;
		Package->dest = dest;
		Package->TTL = TTL;
		Package->seq = seq;
		memcpy(Package->payload, payload, TCP_MAX_PAYLOAD_SIZE);
	}

//Creating the TCPpack
command void Transport.makeTCPPack(TCPpack* TCPheader, uint8_t destPort, uint8_t srcPort, uint16_t seq, uint16_t ack, uint8_t flag, uint8_t advertisedWindow, uint8_t numBytes, uint8_t* payload) {
    dbg(GENERAL_CHANNEL, "\t\t Making the TCP Pack\n");
  	TCPheader->destPort = destPort;
		TCPheader->srcPort = srcPort;
		TCPheader->seq = seq;
		TCPheader->ack = ack;
		TCPheader->flag = flag;
		TCPheader->advertisedWindow = advertisedWindow;
		dbg(GENERAL_CHANNEL, "\t\tSize of TCPheader->payload: %u, payload: %u, numBytes: %u\n", sizeof(TCPheader->payload), sizeof(payload), numBytes);
	 	memcpy(TCPheader->payload, payload, sizeof(payload));
	}

//Creating the SYNpack
command TCPpack* Transport.makeSynPack(TCPpack* TCPheader, uint8_t destPort, uint8_t srcPort, uint16_t seq) {
		TCPheader->destPort = destPort;
		TCPheader->srcPort = srcPort;
    TCPheader->flag = SYN;
		TCPheader->seq = seq;
		dbg(GENERAL_CHANNEL, "\t\tMake SynPack values destPort: %d srcPort: %d seq: %d\n", TCPheader->destPort, TCPheader->srcPort, TCPheader->seq);
		return TCPheader;
	}

//Creating the ACKpack for reply
  command void Transport.makeAckPack(TCPpack* TCPheader, uint8_t destPort, uint8_t srcPort, uint16_t seq, uint8_t flag, uint8_t advertisedWindow) {
  		TCPheader->destPort = destPort;
  		TCPheader->srcPort = srcPort;
      TCPheader->flag = flag;
  		TCPheader->seq = seq;
  		TCPheader->advertisedWindow = advertisedWindow;
  	}

  /**
   * Get a socket if there is one available.
   * @Side Client/Server
   * @return
   *    socket_t - return a socket file descriptor which is a number
   *    associated with a socket. If you are unable to allocated
   *    a socket then return a NULL socket_t.
   */
//Method to get socket file descriptor
    command socket_store_t Transport.getSocket(socket_t fd) {
      return (call sockets.get(fd));
     }

//Look for sockets using destAddr, src, and destPort
command socket_t Transport.findSocket(uint8_t destAddr, uint8_t srcPort, uint8_t destPort) {
		socket_store_t searchSocket;
		uint8_t i;
		uint8_t fd = 1;
		dbg(GENERAL_CHANNEL, "\t\tfindSocket(%u, %u, %u) ->\n", destAddr, srcPort, destPort);
		for (i = 1; i < 11; i++) {
			if(call sockets.contains(i)){
				searchSocket = call sockets.get(i);
				dbg(GENERAL_CHANNEL, "\t\tFound socket!!! src: %u, destPort: %u, destAddr: %u\n", searchSocket.src, searchSocket.dest.port, searchSocket.dest.addr);
				if(searchSocket.src == destAddr && searchSocket.dest.port == srcPort && searchSocket.dest.addr == destPort){
					return (socket_t)i;
				}
			}
		}
	}

//Compute calculated window based off advertised window minus things we have sent
  command uint8_t Transport.calcWindow(socket_store_t* sock, uint16_t advertisedWindow){

  		return advertisedWindow - (sock->lastSent - sock->lastAck - 1);
  	}

//Test if socket is valid based off file descriptor
command bool Transport.isValidSocket(socket_t fd){
		if(call sockets.contains(fd)){
			return TRUE;
    } else return FALSE;
	}

//Sending the packets and socket data
command pack Transport.send(socket_store_t *s, pack IPpack) {
		// Make TCPpack pointer for payload of IP Pack
		TCPpack* data;
		data = (TCPpack*)IPpack.payload;
		dbg(GENERAL_CHANNEL, "\t\tTransport.send()\n");
		dbg(GENERAL_CHANNEL, "\t\tIP PACK LAYER\n");
		dbg(GENERAL_CHANNEL, "\t\t\tSending Packet: Src->%d, Dest-> %d, Seq->%d\n", IPpack.src, IPpack.dest, IPpack.seq);
		dbg(GENERAL_CHANNEL, "\t\t\tSending Packet: TTL->%d\n", IPpack.TTL);
		dbg(GENERAL_CHANNEL, "\t\tTCP PACK LAYER\n");
		dbg(GENERAL_CHANNEL, "\t\t\tSending Packet: destPort->%d, srcPort-> %d, Seq->%d\n", data->destPort, data->srcPort, data->seq);
		dbg(GENERAL_CHANNEL, "\t\t\tSending Packet: ack->%d, numBytes->%d\n", data->ack, data->numBytes);
		if (NeighborList[IPpack.dest] > 0) {
			firstNeighbor = IPpack.dest;
		}
		call Sendor.send(IPpack, firstNeighbor);
		dbg(GENERAL_CHANNEL, "\t\tSocket Data:\n");
		//data->destPort = s->dest.port;
    //data->srcPort = s->src;
		dbg(GENERAL_CHANNEL, "\t\tdestPort: %u, destAddr: %u, srcPort: %u, \n", s->dest.port, s->dest.addr, s->src);
		dbg(GENERAL_CHANNEL, "\t\tsocket->srcPort: %u\n", data->srcPort);
		dbg(GENERAL_CHANNEL, "\t\tData->advertisedWindow: %u, Data->ack: %u\n", data->advertisedWindow, data->ack);
		dbg(GENERAL_CHANNEL, "Sent\n");

		return IPpack;
	}

//Stop and wait packet handling
command void Transport.stopAndWait(socket_store_t sock, uint8_t data, uint16_t IPseqnum) {
		pack msg;
		TCPpack tcp;
		transfer = data;

		dbg(GENERAL_CHANNEL, "\t\tStop and Wait!!! Trasnfer: %u, data: %u\n", transfer, data);
		if(send == TRUE && datasent < transfer){
			//make the TCPpack
			tcpSeq = tcpSeq++;
			tcp.destPort = sock.dest.port;
			tcp.srcPort = sock.src;
			dbg(GENERAL_CHANNEL, "\t\tTCP Seq: %u\n", tcpSeq);
			tcp.seq = tcpSeq;
			tcp.flag = 10;
			tcp.numBytes = sizeof(datasent);
			memcpy(tcp.payload, &datasent, TCP_MAX_PAYLOAD_SIZE);

			sendMessage.dest = sock.dest.addr;
			sendMessage.src = TOS_NODE_ID;
			dbg(GENERAL_CHANNEL, "\t\tIP Seq Before: %u\n", IPseqnum);
			sendMessage.seq = IPseqnum;

			if(IPseq == 0){
				IPseq = IPseqnum;
      }
			sendMessage.TTL = 15;
			sendMessage.protocol = PROTOCOL_TCP;
			memcpy(sendMessage.payload, &tcp, TCP_MAX_PAYLOAD_SIZE);

			dbg(GENERAL_CHANNEL, "\t\tSending num: %u to Node: %u over socket: %u\n", datasent, sock.dest.addr, sock.dest.port);
			//call Transport.send(&sock, msg);
			if (NeighborList[sendMessage.dest] > 0) {
				firstNeighbor = sendMessage.dest;
				dbg(GENERAL_CHANNEL, "\t\tChanged firstNeighbor: %d\n", sendMessage.dest);
			}
			call Sendor.send(sendMessage, firstNeighbor);
			send = FALSE;
			datasent++;

			if(datasent != transfer){
				call timeoutTimer.startOneShot(12000);
      } else call timeoutTimer.stop();
		}
	}

  command socket_t Transport.socket() {
    int i;
		socket_store_t newSocket;
		dbg(GENERAL_CHANNEL, "\tRunning Transport.socket()\n");

    //Check the number of socket keys
    fdKeys++;
    if (fdKeys < 10) {
      newSocket.state = CLOSED;
			newSocket.lastWritten = 0;
			newSocket.lastAck = 255;
			newSocket.lastSent = 0;
			newSocket.lastRead = 0;
			newSocket.lastRcvd = 0;
			newSocket.nextExpected = 0;
			newSocket.RTT = RTT;
			call sockets.insert(fdKeys, newSocket);
			return (socket_t)fdKeys;
    }
    else { //loop through sockets list
      for(i = 0; i < 10; i++)
				if(!call sockets.contains(i))
					return (socket_t)i;
    }

    return (socket_t)NULL;
  }

  /**
   * Bind a socket with an address.
   * @param
   *    socket_t fd: file descriptor that is associated with the socket
   *       you are binding.
   * @param
   *    socket_addr_t *addr: the source port and source address that
   *       you are biding to the socket, fd.
   * @Side Client/Server
   * @return error_t - SUCCESS if you were able to bind this socket, FAIL
   *       if you were unable to bind.
   */
  command error_t Transport.bind(socket_t fd, socket_addr_t *addr) {
    socket_store_t newSocket;
		dbg(GENERAL_CHANNEL, "\tRunning Transport.bind()\n");

    if (call sockets.contains(fd)) {
      newSocket = call sockets.get(fd);
      call sockets.remove(fd);
      newSocket.dest.port = ROOT_SOCKET_PORT;
      newSocket.dest.addr = ROOT_SOCKET_ADDR;
      newSocket.src.port = addr->port;
      newSocket.src.addr = addr->addr;

      dbg(GENERAL_CHANNEL, "\t -- Successful Bind\n");
      //Insert socket back into hashtable
      call sockets.insert(fd, newSocket);
      return SUCCESS;
    }
    dbg(GENERAL_CHANNEL, "\t -- Failed Bind\n");
    return FAIL;
  }

  /**
   * Checks to see if there are socket connections to connect to and
   * if there is one, connect to it.
   * @param
   *    socket_t fd: file descriptor that is associated with the socket
   *       that is attempting an accept. remember, only do on listen.
   * @side Server
   * @return socket_t - returns a new socket if the connection is
   *    accepted. this socket is a copy of the server socket but with
   *    a destination associated with the destination address and port.
   *    if not return a null socket.
   */
  command socket_t Transport.accept(socket_t fd) {
    socket_store_t localSocket;
		dbg(GENERAL_CHANNEL, "\tRunning Transport.accept(%d)\n", fd);
    if (!call sockets.contains(fd)) {
			dbg(GENERAL_CHANNEL, "sockets.contains(fd:  %d) returns false\n", fd);
			return (socket_t)NULL;
		}

    localSocket = call sockets.get(fd);
    if (localSocket.state == LISTEN && numConnected < 10) {

			// Keeping track of used sockets and my destination address, udating state
			numConnected++;
			localSocket.dest.addr = TOS_NODE_ID;
			localSocket.state = SYN_RCVD;

			dbg (GENERAL_CHANNEL, "\t -- localSocket.state: %d localSocket.dest.addr: %d \n", localSocket.state, localSocket.dest.addr);

			// Clearing old and  inserting the modified socket back
			call sockets.remove(fd);
			call sockets.insert(fd, localSocket);
			dbg(GENERAL_CHANNEL, "\t -- returning fd: %d\n", fd);
			return fd;
		}

    return (socket_t) NULL;
  }

  /**
   * Write to the socket from a buffer. This data will eventually be
   * transmitted through your TCP implimentation.
   * @param
   *    socket_t fd: file descriptor that is associated with the socket
   *       that is attempting a write.
   * @param
   *    uint8_t *buff: the buffer data that you are going to wrte from.
   * @param
   *    uint16_t bufflen: The amount of data that you are trying to
   *       submit.
   * @Side For your project, only client side. This could be both though.
   * @return uint16_t - return the amount of data you are able to write
   *    from the pass buffer. This may be shorter then bufflen
   */
  command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen) {
    uint8_t i;
		uint16_t freeSpace, position;
		socket_store_t socket;

		dbg(GENERAL_CHANNEL, "\tRunning Transport.write()\n");

    if(call sockets.contains(fd))
			socket = call sockets.get(fd);

      //Determine how much data we can write, buffer length or write length
      if(socket.lastWritten == socket.lastAck){
        freeSpace = SOCKET_BUFFER_SIZE - 1;
      } else if(socket.lastWritten > socket.lastAck){
        freeSpace = SOCKET_BUFFER_SIZE - (socket.lastWritten - socket.lastAck) - 1;
      } else if(socket.lastWritten < socket.lastAck){
        freeSpace = socket.lastAck - socket.lastWritten - 1;
      } if(freeSpace > bufflen){
        bufflen = freeSpace;
      } if(bufflen == 0){
        dbg(GENERAL_CHANNEL, "\t -- Buffer is Full\n");
        return 0;
      }

      //Iterate through to wite in sendBuff array
      for(i = 0; i < freeSpace; i++) {
        position = (socket.lastWritten + i + 1) % SOCKET_BUFFER_SIZE;
        socket.sendBuff[position] = buff[i];
      }

    //Increment last written position
    socket.lastWritten += position;

  }

  /**
   * This will pass the packet so you can handle it internally.
   * @param
   *    pack *package: the TCP packet that you are handling.
   * @Side Client/Server
   * @return uint16_t - return SUCCESS if you are able to handle this
   *    packet or FAIL if there are errors.
   */
  command error_t Transport.receive(pack* package) {
    pack msg;
		uint8_t temp;
		socket_t fd;
		TCPpack* recievedTcp;
		socket_store_t socket;
		error_t check = FAIL;

    msg = *package;
		recievedTcp = (TCPpack*)package->payload;
    msg.TTL--;

    //switch cases to check what is received
    switch(recievedTcp->flag) {
      case 1://SYN
            dbg(GENERAL_CHANNEL, "\tTransport.recieve: SYN recieved! TTL: %u\n", msg.TTL);

            //Reply with SYN+ACK
            recievedTcp->flag = ACK;
            dbg(GENERAL_CHANNEL, "\t Set Flag to SYN+ACK\n");

            recievedTcp->seq++;
            recievedTcp->advertisedWindow = 1;

            temp = recievedTcp->destPort;
            recievedTcp->destPort = recievedTcp->srcPort;
            recievedTcp->srcPort = temp;

            //Set TCPpack as msg payload
            temp = msg.dest;
            msg.dest = msg.src;
            msg.src = temp;
            msg.seq++;
            msg.TTL = (uint8_t)15;
            msg.protocol = PROTOCOL_TCP;
            memcpy(msg.payload, recievedTcp, TCP_MAX_PAYLOAD_SIZE);

            fd = call Transport.findSocket(recievedTcp->srcPort, ROOT_SOCKET_PORT, ROOT_SOCKET_PORT);
            socket = call sockets.get(fd);

            socket.dest.port = recievedTcp->destPort;
				    socket.dest.addr = msg.dest;
				    socket.state = SYN_RCVD;

            call sockets.remove(fd);
				    call sockets.insert(fd, socket);
            dbg(GENERAL_CHANNEL, "\tsocket.src: %u socket.dest.port: %u\n", socket.src, socket.dest.port);
            call Transport.send(&socket, msg);
				    return  SUCCESS;
				    break;

      case 2://ACK
        dbg(GENERAL_CHANNEL, "\tTransport.receive() default flag ACK\n");

        //swap destPort and srcPort
        temp = recievedTcp->destPort;
				recievedTcp->destPort = recievedTcp->srcPort;
				recievedTcp->srcPort = temp;

        //swap dest and src
        temp = msg.dest;
				msg.dest = msg.src;
				msg.src = temp;
        dbg(GENERAL_CHANNEL, "\t\t recievedTcp->srcPort: %u, msg.src: %u, recievedTcp->destPort: %u msg.dest: %u\n",recievedTcp->srcPort, msg.src, recievedTcp->destPort, msg.dest);

        fd = call Transport.findSocket(recievedTcp->srcPort, recievedTcp->destPort, msg.dest);
        socket = call sockets.get(fd);

        socket.state = ESTABLISHED;
        //Check if we recieved ACK
        if(recievedTcp->ack == tcpSeq + 1 && datasent != transfer){
          send = TRUE;
          call Transport.stopAndWait(socket, transfer, IPseq++);
        }
        call sockets.remove(fd);
				call sockets.insert(fd, socket);
        return SUCCESS;
				break;

      case 3://FIN
        dbg(GENERAL_CHANNEL, "\tTransport.receive() default flag FIN\n");
        call Transport.close(fd, seq);
        break;

      case 4://RST
        dbg(GENERAL_CHANNEL, "\tTransport.receive() default flag RST\n");
				fd = call Transport.findSocket(recievedTcp->destPort, recievedTcp->srcPort, msg.src);
				socket = call sockets.get(fd);
				call sockets.remove(fd);
			//	call sockets.insert(fd, socket);
      return SUCCESS;
				break;

      default:
				return FAIL;
    }
    return check;
  }

  /**
   * Read from the socket and write this data to the buffer. This data
   * is obtained from your TCP implimentation.
   * @param
   *    socket_t fd: file descriptor that is associated with the socket
   *       that is attempting a read.
   * @param
   *    uint8_t *buff: the buffer that is being written.
   * @param
   *    uint16_t bufflen: the amount of data that can be written to the
   *       buffer.
   * @Side For your project, only server side. This could be both though.
   * @return uint16_t - return the amount of data you are able to read
   *    from the pass buffer. This may be shorter then bufflen
   */
  command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen) {
    uint16_t i, pos, len;
		socket_store_t socket;
    dbg(GENERAL_CHANNEL, "\tRunning Transport.read()\n");

    if (!call sockets.contains(fd)) {
			dbg(GENERAL_CHANNEL, "\t -- sockets.contains(fd:  %d) not found!\n", fd);
			return 0;
		}
    else {
      socket = call sockets.get(fd);
      dbg(GENERAL_CHANNEL, "\t -- socket.contains(fd: %d) found!\n", fd);
      }

      //Find our length of read space in buffer
      if(socket.lastRcvd >= socket.lastRead){
        len = socket.lastRcvd - socket.lastRead;
      } else if(socket.lastRcvd < socket.lastRead) {
        len = SOCKET_BUFFER_SIZE - socket.lastRead + socket.lastRcvd;
      }
      dbg(GENERAL_CHANNEL, "\t -- Read Space Length: %d\n", len);

      //Min value from length and buffer length
      if(len > bufflen){
        len = bufflen;
      }
      dbg(GENERAL_CHANNEL, "\t -- Min Space Between Length and Bufferlen: %d\n", len);

      //Space gap in buffer ready to be read
      if(socket.nextExpected <= socket.lastRcvd + 1){
        len = socket.nextExpected - socket.lastRead;
      }
      dbg(GENERAL_CHANNEL, "\t -- Length Ready To Be Read: %d\n", len);

      //Iterate through length to know how long we can read
      for(i = 0; i < len; i++)
      {
        pos = (socket.lastRead + i) % SOCKET_BUFFER_SIZE;
        buff[i] = socket.rcvdBuff[pos];
      }

      socket.lastRead += len;
      call sockets.insert(fd, socket);
      dbg(GENERAL_CHANNEL, "\t -- Length: %d\n", len);
      return len;

  }

  /**
   * Attempts a connection to an address.
   * @param
   *    socket_t fd: file descriptor that is associated with the socket
   *       that you are attempting a connection with.
   * @param
   *    socket_addr_t *addr: the destination address and port where
   *       you will atempt a connection.
   * @side Client
   * @return socket_t - returns SUCCESS if you are able to attempt
   *    a connection with the fd passed, else return FAIL.
   */
  command error_t Transport.connect(socket_t fd, socket_addr_t * addr) {
    socket_store_t newConnection;
		uint16_t seq;
		pack msg;
		uint8_t TTL;
		TCPpack* tcp_msg;
		uint8_t* payload = 0;
		TTL = 18;

    dbg(GENERAL_CHANNEL, "\tRunning Transport.connect(%u,%d)\n", fd, addr->addr);

    //Check if the socket is in the socket hashmap
    if (call sockets.contains(fd)) {
      newConnection = call sockets.get(fd);
			call sockets.remove(fd);

      //Set destination port
      newConnection.dest = *addr;

      //Send SYN packet
      tcp_msg->destPort = newConnection.dest.port;
      tcp_msg->srcPort = newConnection.src;
      tcp_msg->seq = seq;
			tcp_msg->flag = SYN;
			tcp_msg->numBytes = 0;
      msg.dest = newConnection.dest.addr;
			msg.src = TOS_NODE_ID;
			msg.seq = seq;
			msg.TTL = ttl;
			msg.protocol = PROTOCOL_TCP;
			memcpy(msg.payload, (void*)tcp_msg, TCP_MAX_PAYLOAD_SIZE);
      /*call Transport.makePack(&msg, (uint16_t)TOS_NODE_ID, (uint16_t)newConnection.src,
						(uint16_t)19,	PROTOCOL_TCP,(uint16_t)1,(void*)tcp_msg,(uint8_t)sizeof(tcp_msg));*/
      newConnection.state = SYN_SENT;
      call Transport.send(&newConnection, msg);

      //Update hashtable
      call sockets.insert(fd, newConnection);
      return SUCCESS
    }
    else return FAIL;
  }

  /**
   * Closes the socket.
   * @param
   *    socket_t fd: file descriptor that is associated with the socket
   *       that you are closing.
   * @side Client/Server
   * @return socket_t - returns SUCCESS if you are able to attempt
   *    a closure with the fd passed, else return FAIL.
   */

   //Close connection by removing socket from the list of active connections
  command error_t Transport.close(socket_t fd, uint16_t seq) {
    socket_store_t socket;
    pack msg;
    TCPpack* tcp_msg;
    dbg(GENERAL_CHANNEL, "Transport Close\n");

    if(call sockets.contains(fd)) {
      socket = call sockets.get(fd);
      dbg(GENERAL_CHANNEL, "Here 1\n");
      tcp_msg->destPort = socket.dest.port;
      dbg(GENERAL_CHANNEL, "Here 1\n");
      tcp_msg->seq = seq;
      tcp_msg->flag = RST;
      tcp_msg->srcPort = socket.src;
      dbg(GENERAL_CHANNEL, "Here 1\n");
      tcp_msg->numBytes = 0;
      dbg(GENERAL_CHANNEL, "Here 2\n");
      msg.dest = socket.dest.address;
      msg.src = TOS_NODE_ID;
      msg.seq = seq;
      msg.TTL = 15;
      msg.protocol = PROTOCOL_TCP;
      dbg(GENERAL_CHANNEL, "Here 3\n");
      memcpy(msg.payload, (void*)tcp_msg, TCP_MAX_PAYLOAD_SIZE);
      call sockets.remove(fd);
      call sockets.insert(fd, socket);
      dbg(GENERAL_CHANNEL, "Here 4\n");
      call Transport.send(&socket, msg);
    }
    else {
      dbg(GENERAL_CHANNEL, "CANNOT CLOSE");
      return FAIL;
    }
    return SUCCESS;
    }

  /**
   * A hard close, which is not graceful. This portion is optional.
   * @param
   *    socket_t fd: file descriptor that is associated with the socket
   *       that you are hard closing.
   * @side Client/Server
   * @return socket_t - returns SUCCESS if you are able to attempt
   *    a closure with the fd passed, else return FAIL.
   */
  command error_t Transport.release(socket_t fd) {
    return FAIL;
  }

  /**
   * Listen to the socket and wait for a connection.
   * @param
   *    socket_t fd: file descriptor that is associated with the socket
   *       that you are hard closing.
   * @side Server
   * @return error_t - returns SUCCESS if you are able change the state
   *   to listen else FAIL.
   */
   //finishhhh
  command error_t Transport.listen(socket_t fd) {
    socket_store_t socket;
		dbg(GENERAL_CHANNEL, "\tRunning Transport.listen()\n");

    //Check hashmap of sockets if fd is in
    if (call sockets.contains(fd)) {
      socket = call sockets.get(fd);
			call sockets.remove(fd);
      socket.state = LISTEN;
      call sockets.insert(fd, socket);
      return SUCCESS;
    }

    return FAIL;
  }

  command socket_t Transport.findSocket(uint16_t dest, uint8_t srcPort, uint8_t destPort){


  }

}
