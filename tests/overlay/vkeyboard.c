// SPDX-License-Identifier: GPL-3.0-or-later
//
// vkeyboard: real key presses for the M2 gate inside the nest, through the compositor's virtual-keyboard protocol
// (zwp_virtual_keyboard_manager_v1). The compositor treats them as keys of a keyboard: its binds see them (Hyprland
// ignores a virtual keyboard only when it belongs to the input method), so a key bound to the `global` dispatcher
// reaches the overview's GlobalShortcut exactly as Marc's keyboard would.
//
//   vkeyboard serve     one virtual keyboard for the whole run: connects, uploads a US keymap, then reads commands
//                       from stdin, one per line, and answers on stdout once the compositor took the events:
//                         tap KEY [KEY...]   press the keys in order, then release them in reverse order
//                         down KEY | up KEY  one press or one release
//                       The answer is "ok T0", T0 the wall clock (ms since the epoch, as Date.now() and Python's
//                       time.time() count) read immediately before the first key event of the command is written to
//                       the compositor; or "error ...".
//   KEY: super (left Super), a, f9, escape.
//
// It stays connected between commands, so a timed key press includes no process start, no connection and no keymap
// upload: only the key event itself. The modifier state sent after each key comes from libxkbcommon's state for the
// same keymap, as a real keyboard's would. The two interfaces are declared here by hand (the protocol's requests in
// their order), so no XML is needed.
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>

static const struct wl_interface vk_interface;
static const struct wl_interface *vk_types[] = {
    NULL, NULL, NULL, NULL,
    &wl_seat_interface, &vk_interface,                        // create_virtual_keyboard(seat, new_id)
};
static const struct wl_message vk_requests[] = {
    { "keymap", "uhu", vk_types },
    { "key", "uuu", vk_types },
    { "modifiers", "uuuu", vk_types },
    { "destroy", "", vk_types },
};
static const struct wl_interface vk_interface = {
    "zwp_virtual_keyboard_v1", 1, 4, vk_requests, 0, NULL,
};
static const struct wl_message vkm_requests[] = {
    { "create_virtual_keyboard", "on", vk_types + 4 },
};
static const struct wl_interface vkm_interface = {
    "zwp_virtual_keyboard_manager_v1", 1, 1, vkm_requests, 0, NULL,
};

enum { VK_KEYMAP = 0, VK_KEY = 1, VK_MODIFIERS = 2, VK_DESTROY = 3, VKM_CREATE = 0 };

static struct wl_proxy *manager;
static struct wl_seat *seat;
static struct xkb_state *xstate;

static void global_add(void *data, struct wl_registry *reg, uint32_t name, const char *iface, uint32_t version) {
    (void)data;
    (void)version;
    if (strcmp(iface, vkm_interface.name) == 0)
        manager = wl_registry_bind(reg, name, &vkm_interface, 1);
    else if (strcmp(iface, wl_seat_interface.name) == 0 && !seat)
        seat = wl_registry_bind(reg, name, &wl_seat_interface, 1);
}

static void global_remove(void *data, struct wl_registry *reg, uint32_t name) {
    (void)data;
    (void)reg;
    (void)name;
}

static const struct wl_registry_listener registry_listener = { global_add, global_remove };

static uint32_t mono_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint32_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

static double wall_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (double)ts.tv_sec * 1000.0 + (double)ts.tv_nsec / 1e6;
}

static int key_code(const char *name) {
    // linux/input-event-codes.h
    if (strcmp(name, "super") == 0) return 125;   // KEY_LEFTMETA
    if (strcmp(name, "a") == 0) return 30;        // KEY_A
    if (strcmp(name, "f9") == 0) return 67;       // KEY_F9
    if (strcmp(name, "escape") == 0) return 1;    // KEY_ESC
    return -1;
}

// One key event, then the modifier state it leaves (xkb keycodes are evdev codes plus 8).
static void key(struct wl_proxy *vk, int code, int pressed) {
    wl_proxy_marshal_flags(vk, VK_KEY, NULL, 1, 0, mono_ms(), (uint32_t)code, (uint32_t)(pressed ? 1 : 0));
    xkb_state_update_key(xstate, (xkb_keycode_t)(code + 8), pressed ? XKB_KEY_DOWN : XKB_KEY_UP);
    wl_proxy_marshal_flags(vk, VK_MODIFIERS, NULL, 1, 0,
                           xkb_state_serialize_mods(xstate, XKB_STATE_MODS_DEPRESSED),
                           xkb_state_serialize_mods(xstate, XKB_STATE_MODS_LATCHED),
                           xkb_state_serialize_mods(xstate, XKB_STATE_MODS_LOCKED),
                           xkb_state_serialize_layout(xstate, XKB_STATE_LAYOUT_EFFECTIVE));
}

static int serve(struct wl_display *dpy, struct wl_proxy *vk) {
    char line[256];
    setvbuf(stdout, NULL, _IOLBF, 0);
    while (fgets(line, sizeof line, stdin)) {
        char cmd[32] = "";
        int codes[8], n = 0, off = 0, used = 0;
        if (sscanf(line, "%31s%n", cmd, &off) != 1) continue;
        char word[32];
        const char *p = line + off;
        int bad = 0;
        while (n < 8 && sscanf(p, "%31s%n", word, &used) == 1) {
            int c = key_code(word);
            if (c < 0) { bad = 1; break; }
            codes[n++] = c;
            p += used;
        }
        int is_tap = strcmp(cmd, "tap") == 0, is_down = strcmp(cmd, "down") == 0, is_up = strcmp(cmd, "up") == 0;
        if (bad || n == 0 || !(is_tap || ((is_down || is_up) && n == 1))) {
            printf("error %s", line);
            continue;
        }
        const double t0 = wall_ms();
        if (is_tap) {
            for (int i = 0; i < n; i++) key(vk, codes[i], 1);
            wl_display_flush(dpy);                     // the press goes out now, not with the release
            for (int i = n - 1; i >= 0; i--) key(vk, codes[i], 0);
        } else {
            key(vk, codes[0], is_down);
        }
        wl_display_roundtrip(dpy);
        printf("ok %.3f\n", t0);
    }
    return 0;
}

int main(int argc, char **argv) {
    if (argc != 2 || strcmp(argv[1], "serve") != 0) {
        fprintf(stderr, "usage: vkeyboard serve\n");
        return 2;
    }
    struct wl_display *dpy = wl_display_connect(NULL);
    if (!dpy) {
        fprintf(stderr, "vkeyboard: no Wayland display\n");
        return 1;
    }
    struct wl_registry *reg = wl_display_get_registry(dpy);
    wl_registry_add_listener(reg, &registry_listener, NULL);
    wl_display_roundtrip(dpy);
    if (!manager || !seat) {
        fprintf(stderr, "vkeyboard: the compositor has no %s or no seat\n", vkm_interface.name);
        return 1;
    }
    struct xkb_context *ctx = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    struct xkb_rule_names names = { "evdev", "pc105", "us", "", "" };
    struct xkb_keymap *km = ctx ? xkb_keymap_new_from_names(ctx, &names, XKB_KEYMAP_COMPILE_NO_FLAGS) : NULL;
    char *text = km ? xkb_keymap_get_as_string(km, XKB_KEYMAP_FORMAT_TEXT_V1) : NULL;
    if (!text) {
        fprintf(stderr, "vkeyboard: no US keymap from libxkbcommon\n");
        return 1;
    }
    xstate = xkb_state_new(km);
    size_t size = strlen(text) + 1;
    int fd = memfd_create("vkeyboard-keymap", MFD_CLOEXEC);
    if (fd < 0 || write(fd, text, size) != (ssize_t)size) {
        fprintf(stderr, "vkeyboard: cannot write the keymap\n");
        return 1;
    }
    struct wl_proxy *vk = wl_proxy_marshal_flags(manager, VKM_CREATE, &vk_interface, 1, 0, seat, NULL);
    wl_proxy_marshal_flags(vk, VK_KEYMAP, NULL, 1, 0, (uint32_t)XKB_KEYMAP_FORMAT_TEXT_V1, fd, (uint32_t)size);
    wl_display_roundtrip(dpy);
    close(fd);
    free(text);
    serve(dpy, vk);
    wl_proxy_marshal_flags(vk, VK_DESTROY, NULL, 1, WL_MARSHAL_FLAG_DESTROY);
    wl_display_roundtrip(dpy);
    wl_display_disconnect(dpy);
    return 0;
}
