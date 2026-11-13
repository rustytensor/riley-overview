// SPDX-License-Identifier: GPL-3.0-or-later
//
// vpointer: real pointer input for the M2 gate inside the nest, through the compositor's virtual-pointer protocol
// (zwlr_virtual_pointer_manager_v1). A cursor warp (hl.dsp.cursor.move) moves the cursor but sends no motion to the
// surface under it, so a hover check needs a real motion event:
//
//   vpointer move DX DY      one relative motion of DX, DY logical px, then a frame
//
// It connects to $WAYLAND_DISPLAY (the nest's), sends the event, waits for the compositor to take it and exits.
// The two interfaces are declared here by hand (the protocol's requests in their order), so no XML is needed.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <wayland-client.h>

static const struct wl_interface vp_interface;
static const struct wl_interface *vp_types[] = {
    NULL, NULL, NULL, NULL, NULL,
    &wl_seat_interface, &vp_interface,                        // create_virtual_pointer(seat?, new_id)
    &wl_seat_interface, &wl_output_interface, &vp_interface,  // create_virtual_pointer_with_output(seat?, output?, new_id)
};
static const struct wl_message vp_requests[] = {
    { "motion", "uff", vp_types },
    { "motion_absolute", "uuuuu", vp_types },
    { "button", "uuu", vp_types },
    { "axis", "uuf", vp_types },
    { "frame", "", vp_types },
    { "axis_source", "u", vp_types },
    { "axis_stop", "uu", vp_types },
    { "axis_discrete", "uufi", vp_types },
    { "destroy", "", vp_types },
};
static const struct wl_interface vp_interface = {
    "zwlr_virtual_pointer_v1", 1, 9, vp_requests, 0, NULL,
};
static const struct wl_message vpm_requests[] = {
    { "create_virtual_pointer", "?on", vp_types + 5 },
    { "destroy", "", vp_types },
    { "create_virtual_pointer_with_output", "2?o?on", vp_types + 7 },
};
static const struct wl_interface vpm_interface = {
    "zwlr_virtual_pointer_manager_v1", 1, 3, vpm_requests, 0, NULL,
};

enum { VP_MOTION = 0, VP_FRAME = 4, VP_DESTROY = 8, VPM_CREATE = 0, VPM_DESTROY = 1 };

static struct wl_proxy *manager;

static void global_add(void *data, struct wl_registry *reg, uint32_t name, const char *iface, uint32_t version) {
    (void)data;
    (void)version;
    if (strcmp(iface, vpm_interface.name) == 0)
        manager = wl_registry_bind(reg, name, &vpm_interface, 1);
}

static void global_remove(void *data, struct wl_registry *reg, uint32_t name) {
    (void)data;
    (void)reg;
    (void)name;
}

static const struct wl_registry_listener registry_listener = { global_add, global_remove };

static uint32_t now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint32_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

int main(int argc, char **argv) {
    if (argc != 4 || strcmp(argv[1], "move") != 0) {
        fprintf(stderr, "usage: vpointer move DX DY\n");
        return 2;
    }
    double dx = atof(argv[2]), dy = atof(argv[3]);
    struct wl_display *dpy = wl_display_connect(NULL);
    if (!dpy) {
        fprintf(stderr, "vpointer: no Wayland display\n");
        return 1;
    }
    struct wl_registry *reg = wl_display_get_registry(dpy);
    wl_registry_add_listener(reg, &registry_listener, NULL);
    wl_display_roundtrip(dpy);
    if (!manager) {
        fprintf(stderr, "vpointer: the compositor has no %s\n", vpm_interface.name);
        return 1;
    }
    struct wl_proxy *vp = wl_proxy_marshal_flags(manager, VPM_CREATE, &vp_interface, 1, 0, NULL, NULL);
    wl_display_roundtrip(dpy);
    wl_proxy_marshal_flags(vp, VP_MOTION, NULL, 1, 0, now_ms(), wl_fixed_from_double(dx), wl_fixed_from_double(dy));
    wl_proxy_marshal_flags(vp, VP_FRAME, NULL, 1, 0);
    wl_display_roundtrip(dpy);
    wl_proxy_marshal_flags(vp, VP_DESTROY, NULL, 1, WL_MARSHAL_FLAG_DESTROY);
    wl_proxy_marshal_flags(manager, VPM_DESTROY, NULL, 1, WL_MARSHAL_FLAG_DESTROY);
    wl_display_roundtrip(dpy);
    wl_display_disconnect(dpy);
    return 0;
}
