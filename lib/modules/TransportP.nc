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

     uses interface Hashmap<socket_store_t> as sockets;
 }

implementation {
  uint16_t RTT = 12000;
  uint16_t fdKeys = 0; //number of fdKeys we currently have
  uint8_t numConnected = 0; //number of connected sockets


  command void Transport.makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length) {
		tcp_packet* tcpp = (tcp_packet*) payload;

		Package->src = src;
		Package->dest = dest;
		Package->TTL = TTL;
		Package->seq = seq;
		memcpy(Package->payload, payload, TCP_MAX_PAYLOAD_SIZE);
	}

  command socket_store_t Transport.getSocket(socket_t fd) {
    if(call sockets.contains(fd))
    return (call sockets.get(fd));
  else
    return (socket_store_t) NULL;
  }

  /**
   * Get a socket if there is one available.
   * @Side Client/Server
   * @return
   *    socket_t - return a socket file descriptor which is a number
   *    associated with a socket. If you are unable to allocated
   *    a socket then return a NULL socket_t.
   */
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

    return (socket_t) null;
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
		tcp_packet* recievedTcp;
		socket_store_t socket;
		error_t check = FAIL;

    msg = *package;
		recievedTcp = (tcp_packet*)package->payload;
    msg.TTL--;

    //switch cases to check what is received
    switch(recievedTcp->flag) {
      case 1://SYN
            dbg(GENERAL_CHANNEL, "\tTransport.recieve: SYN recieved! TTL: %u\n", msg.TTL);

            //Reply with SYN+ACK
            recievedTcp->flag = ACK;
            dbg(GENERAL_CHANNEL, "\t Set Flag to SYN+ACK\n");

            recievedTcp->seq++;
            //recievedTcp->advertisedWindow = 1;

            temp = recievedTcp->destPort;
            recievedTcp->destPort = recievedTcp->srcPort;
            recievedTcp->srcPort = temp;

            temp = msg.dest;
            msg.dest = msg.src;
            msg.src = temp;
            msg.seq++;
            msg.TTL = (uint8_t)15;
            msg.protocol = PROTOCOL_TCP;
            memcpy(msg.payload, recievedTcp, TCP_MAX_PAYLOAD_SIZE);

      case 2://ACK
      case 3://FIN
      case 4://RST
    }
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
        len = socket.lastRcvd - socket.lastRead
      } else if(socket.lastRcvd < socket.lastRead) {
        len = SOCKET_BUFFER_SIZE - socket.lastRead + socket.lastRcvd
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
