#ifndef TCPpack_H
#define TCPpack_H

enum{
	TCP_HEADER_LENGTH = 9,
	//PACKET_MAX_PAYLOAD_SIZE
  TCP_MAX_PAYLOAD_SIZE = 20 - TCP_HEADER_LENGTH
};

typedef nx_struct TCPpack{
	nx_uint8_t destPort;
	nx_uint8_t srcPort;
	nx_uint16_t seq;		//Sequence Number
	nx_uint16_t ack;		//Time to Live
	nx_uint8_t flag;
  nx_uint8_t advertisedWindow;
  nx_uint8_t numBytes;
	nx_uint8_t payload[TCP_MAX_PAYLOAD_SIZE];
}TCPpack;

enum{
  SYN = 1,
  ACK = 2,
  FIN = 4,
  RST= 8
};

#endif
