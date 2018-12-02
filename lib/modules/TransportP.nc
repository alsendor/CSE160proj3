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

  command void Transport.makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length) {
		tcp_packet* tcpp = (tcp_packet*) payload;

		Package->src = src;
		Package->dest = dest;
		Package->TTL = TTL;
		Package->seq = seq;
		memcpy(Package->payload, payload, TCP_MAX_PAYLOAD_SIZE);
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
    return SUCCESS;
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
