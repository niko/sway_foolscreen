// Minimal Wayland window that only fills its area with a solid color.
// Usage: foolscreen-placeholder [-c RRGGBB|AARRGGBB] <app_id> <title>
// Build: make
#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <wayland-client.h>
#include "xdg-shell-client-protocol.h"

static struct wl_compositor *compositor;
static struct wl_shm *shm;
static struct xdg_wm_base *wm_base;
static struct wl_surface *surface;
static int32_t width = 1, height = 1, drawn_width, drawn_height;
static int running = 1;
static uint32_t color = 0xff202020; // premultiplied ARGB

static void buffer_release(void *data, struct wl_buffer *buffer) {
    wl_buffer_destroy(buffer);
}
static const struct wl_buffer_listener buffer_listener = { buffer_release };

static void draw(void) {
    int stride = width * 4, size = stride * height;
    int fd = memfd_create("placeholder", MFD_CLOEXEC);
    ftruncate(fd, size);
    uint32_t *pixels = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    for (int i = 0; i < width * height; i++) pixels[i] = color;
    munmap(pixels, size);
    struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, size);
    struct wl_buffer *buffer = wl_shm_pool_create_buffer(pool, 0, width, height, stride, WL_SHM_FORMAT_ARGB8888);
    wl_shm_pool_destroy(pool);
    close(fd);
    wl_buffer_add_listener(buffer, &buffer_listener, NULL);
    wl_surface_attach(surface, buffer, 0, 0);
    wl_surface_damage_buffer(surface, 0, 0, width, height);
    drawn_width = width;
    drawn_height = height;
}

static void wm_base_ping(void *data, struct xdg_wm_base *base, uint32_t serial) {
    xdg_wm_base_pong(base, serial);
}
static const struct xdg_wm_base_listener wm_base_listener = { wm_base_ping };

static void xdg_surface_configure(void *data, struct xdg_surface *xdg_surface, uint32_t serial) {
    xdg_surface_ack_configure(xdg_surface, serial);
    if (width != drawn_width || height != drawn_height) draw();
    wl_surface_commit(surface);
}
static const struct xdg_surface_listener xdg_surface_listener = { xdg_surface_configure };

static void toplevel_configure(void *data, struct xdg_toplevel *toplevel, int32_t w, int32_t h, struct wl_array *states) {
    if (w > 0 && h > 0) {
        width = w;
        height = h;
    }
}
static void toplevel_close(void *data, struct xdg_toplevel *toplevel) {
    running = 0;
}
static void toplevel_configure_bounds(void *data, struct xdg_toplevel *toplevel, int32_t w, int32_t h) {}
static void toplevel_wm_capabilities(void *data, struct xdg_toplevel *toplevel, struct wl_array *caps) {}
static const struct xdg_toplevel_listener toplevel_listener = {
    toplevel_configure, toplevel_close, toplevel_configure_bounds, toplevel_wm_capabilities,
};

static void registry_global(void *data, struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version) {
    if (strcmp(interface, wl_compositor_interface.name) == 0)
        compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 4);
    else if (strcmp(interface, wl_shm_interface.name) == 0)
        shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
    else if (strcmp(interface, xdg_wm_base_interface.name) == 0)
        wm_base = wl_registry_bind(registry, name, &xdg_wm_base_interface, 1);
}
static void registry_global_remove(void *data, struct wl_registry *registry, uint32_t name) {}
static const struct wl_registry_listener registry_listener = { registry_global, registry_global_remove };

// parse RRGGBB or AARRGGBB into premultiplied ARGB
static int parse_color(const char *s) {
    size_t len = strlen(s);
    if ((len != 6 && len != 8) || strspn(s, "0123456789abcdefABCDEF") != len) return 0;
    uint32_t c = strtoul(s, NULL, 16);
    if (len == 6) c |= 0xff000000;
    uint32_t a = c >> 24;
    color = a << 24 | ((c >> 16 & 0xff) * a / 255) << 16 | ((c >> 8 & 0xff) * a / 255) << 8 | (c & 0xff) * a / 255;
    return 1;
}

static int usage(const char *name) {
    fprintf(stderr, "usage: %s [-c RRGGBB|AARRGGBB] <app_id> <title>\n", name);
    return 1;
}

int main(int argc, char **argv) {
    int opt;
    while ((opt = getopt(argc, argv, "c:")) != -1)
        if (opt != 'c' || !parse_color(optarg)) return usage(argv[0]);
    if (argc - optind != 2) return usage(argv[0]);
    const char *app_id = argv[optind], *title = argv[optind + 1];
    struct wl_display *display = wl_display_connect(NULL);
    if (!display) {
        fprintf(stderr, "cannot connect to wayland display\n");
        return 1;
    }
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);
    xdg_wm_base_add_listener(wm_base, &wm_base_listener, NULL);

    surface = wl_compositor_create_surface(compositor);
    struct xdg_surface *xdg_surface = xdg_wm_base_get_xdg_surface(wm_base, surface);
    xdg_surface_add_listener(xdg_surface, &xdg_surface_listener, NULL);
    struct xdg_toplevel *toplevel = xdg_surface_get_toplevel(xdg_surface);
    xdg_toplevel_add_listener(toplevel, &toplevel_listener, NULL);
    xdg_toplevel_set_app_id(toplevel, app_id);
    xdg_toplevel_set_title(toplevel, title);
    wl_surface_commit(surface);

    while (running && wl_display_dispatch(display) != -1) {}
    return 0;
}
