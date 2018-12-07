#include "../../includes/socket.h"
#include "../../includes/packet.h"
#include "../../includes/am_types.h"

configuration TransportC{
   provides interface Transport;
}

implementation {
  components TransportP;
  Transport = TransportP;

  components new Hashmap(socket_store_t, 10);
  TransportP.sockets -> HashmapC;

  components RandomC as Random;
  TransportP.Random -> Random;

  components new SimpleSendC(AM_PACK);
  TransportP.Sendor -> SimpleSendC;

  components new TimerMilliC() as Timer1;
  TransportP.timeoutTimer -> Timer1;
}
