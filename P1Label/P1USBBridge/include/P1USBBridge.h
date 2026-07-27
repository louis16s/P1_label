#ifndef P1USBBridge_h
#define P1USBBridge_h

#include <stddef.h>
#include <stdint.h>

typedef struct P1USBConnection P1USBConnection;

typedef enum P1USBResult {
    P1USBResultOK = 0,
    P1USBResultNotFound = 1,
    P1USBResultOpenFailed = 2,
    P1USBResultInterfaceNotFound = 3,
    P1USBResultClaimFailed = 4,
    P1USBResultWriteFailed = 5,
    P1USBResultInvalidArgument = 6,
    P1USBResultReadFailed = 7,
} P1USBResult;

int p1_usb_is_present(void);
P1USBConnection *p1_usb_open(P1USBResult *result);
P1USBResult p1_usb_send(P1USBConnection *connection, const uint8_t *bytes, size_t length);
P1USBResult p1_usb_get_port_status(P1USBConnection *connection, uint8_t *status);
void p1_usb_close(P1USBConnection *connection);

#endif
