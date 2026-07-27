#include "P1USBBridge.h"
#include <libusb-1.0/libusb.h>
#include <stdlib.h>

#define P1_VENDOR_ID 0x3533
#define P1_PRODUCT_ID 0x5A11

struct P1USBConnection {
    libusb_context *context;
    libusb_device_handle *handle;
    int interface_number;
    unsigned char out_endpoint;
};

static void set_result(P1USBResult *result, P1USBResult value) {
    if (result) *result = value;
}

int p1_usb_is_present(void) {
    libusb_context *context = NULL;
    if (libusb_init(&context) != 0) return 0;

    libusb_device **devices = NULL;
    ssize_t count = libusb_get_device_list(context, &devices);
    int present = 0;
    if (count >= 0) {
        for (ssize_t index = 0; index < count; index++) {
            struct libusb_device_descriptor descriptor;
            if (libusb_get_device_descriptor(devices[index], &descriptor) == 0 &&
                descriptor.idVendor == P1_VENDOR_ID &&
                descriptor.idProduct == P1_PRODUCT_ID) {
                present = 1;
                break;
            }
        }
        libusb_free_device_list(devices, 1);
    }
    libusb_exit(context);
    return present;
}

P1USBConnection *p1_usb_open(P1USBResult *result) {
    set_result(result, P1USBResultOpenFailed);

    P1USBConnection *connection = calloc(1, sizeof(P1USBConnection));
    if (!connection || libusb_init(&connection->context) != 0) {
        free(connection);
        return NULL;
    }

    connection->handle = libusb_open_device_with_vid_pid(connection->context, P1_VENDOR_ID, P1_PRODUCT_ID);
    if (!connection->handle) {
        libusb_exit(connection->context);
        free(connection);
        set_result(result, P1USBResultNotFound);
        return NULL;
    }

    libusb_device *device = libusb_get_device(connection->handle);
    struct libusb_config_descriptor *config = NULL;
    if (libusb_get_active_config_descriptor(device, &config) != 0) {
        libusb_close(connection->handle);
        libusb_exit(connection->context);
        free(connection);
        return NULL;
    }

    int found = 0;
    for (uint8_t i = 0; i < config->bNumInterfaces && !found; i++) {
        const struct libusb_interface *interface = &config->interface[i];
        for (int alt = 0; alt < interface->num_altsetting && !found; alt++) {
            const struct libusb_interface_descriptor *descriptor = &interface->altsetting[alt];
            if (descriptor->bInterfaceClass != LIBUSB_CLASS_PRINTER) continue;
            for (uint8_t endpoint = 0; endpoint < descriptor->bNumEndpoints; endpoint++) {
                const struct libusb_endpoint_descriptor *candidate = &descriptor->endpoint[endpoint];
                if ((candidate->bmAttributes & LIBUSB_TRANSFER_TYPE_MASK) == LIBUSB_TRANSFER_TYPE_BULK &&
                    (candidate->bEndpointAddress & LIBUSB_ENDPOINT_DIR_MASK) == LIBUSB_ENDPOINT_OUT) {
                    connection->interface_number = descriptor->bInterfaceNumber;
                    connection->out_endpoint = candidate->bEndpointAddress;
                    found = 1;
                    break;
                }
            }
        }
    }
    libusb_free_config_descriptor(config);

    if (!found) {
        libusb_close(connection->handle);
        libusb_exit(connection->context);
        free(connection);
        set_result(result, P1USBResultInterfaceNotFound);
        return NULL;
    }

    libusb_set_auto_detach_kernel_driver(connection->handle, 1);
    if (libusb_claim_interface(connection->handle, connection->interface_number) != 0) {
        libusb_close(connection->handle);
        libusb_exit(connection->context);
        free(connection);
        set_result(result, P1USBResultClaimFailed);
        return NULL;
    }

    set_result(result, P1USBResultOK);
    return connection;
}

P1USBResult p1_usb_send(P1USBConnection *connection, const uint8_t *bytes, size_t length) {
    if (!connection || !bytes || length == 0) return P1USBResultInvalidArgument;

    size_t offset = 0;
    while (offset < length) {
        int transferred = 0;
        int chunk = (int)((length - offset) > 4096 ? 4096 : (length - offset));
        int code = libusb_bulk_transfer(connection->handle, connection->out_endpoint,
                                        (unsigned char *)(bytes + offset), chunk,
                                        &transferred, 5000);
        if (code != 0 || transferred <= 0) return P1USBResultWriteFailed;
        offset += (size_t)transferred;
    }
    return P1USBResultOK;
}

P1USBResult p1_usb_get_port_status(P1USBConnection *connection, uint8_t *status) {
    if (!connection || !status) return P1USBResultInvalidArgument;
    unsigned char value = 0;
    int transferred = libusb_control_transfer(
        connection->handle,
        LIBUSB_ENDPOINT_IN | LIBUSB_REQUEST_TYPE_CLASS | LIBUSB_RECIPIENT_INTERFACE,
        1,
        0,
        (uint16_t)connection->interface_number,
        &value,
        1,
        1000
    );
    if (transferred != 1) return P1USBResultReadFailed;
    *status = value;
    return P1USBResultOK;
}

void p1_usb_close(P1USBConnection *connection) {
    if (!connection) return;
    if (connection->handle) {
        libusb_release_interface(connection->handle, connection->interface_number);
        libusb_close(connection->handle);
    }
    if (connection->context) libusb_exit(connection->context);
    free(connection);
}
