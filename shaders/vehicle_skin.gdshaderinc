// Persistent vehicle vertices bind to the actual native particles. No rigid-body
// substitute: paint, glass, cage, rims and tires all follow the same solver.
uniform vec3 node_positions[100];
uniform vec3 ring_centers[8];
uniform vec3 rig_center = vec3(0.0);
uniform float tire_padding = 0.0552;
varying vec3 bind_position;

vec3 box_skin(int b, vec3 p) {
    vec3 low = mix(mix(node_positions[b], node_positions[b + 1], p.x),
                   mix(node_positions[b + 2], node_positions[b + 3], p.x), p.z);
    vec3 high = mix(mix(node_positions[b + 4], node_positions[b + 5], p.x),
                    mix(node_positions[b + 6], node_positions[b + 7], p.x), p.z);
    return mix(low, high, p.y);
}
vec3 box_normal(int b, vec3 p, vec3 n) {
    vec3 dx = box_skin(b, vec3(1.0, p.y, p.z)) - box_skin(b, vec3(0.0, p.y, p.z));
    vec3 dy = box_skin(b, vec3(p.x, 1.0, p.z)) - box_skin(b, vec3(p.x, 0.0, p.z));
    vec3 dz = box_skin(b, vec3(p.x, p.y, 1.0)) - box_skin(b, vec3(p.x, p.y, 0.0));
    // Cofactors are inverse-transpose up to a common determinant. This remains
    // finite when severe crashes collapse a cell (unlike matrix inversion).
    vec3 result = cross(dy, dz) * n.x + cross(dz, dx) * n.y + cross(dx, dy) * n.z;
    return length(result) > 0.000001 ? normalize(result) : vec3(0.0, 1.0, 0.0);
}
vec3 ring_sample(int first, float phase) {
    float f = fract(phase) * 10.0;
    int k = int(floor(f));
    float t = fract(f);
    vec3 a = node_positions[first + (k + 9) % 10];
    vec3 b = node_positions[first + k];
    vec3 c = node_positions[first + (k + 1) % 10];
    vec3 d = node_positions[first + (k + 2) % 10];
    // Catmull-Rom passes through every physical ring node. Extra render vertices
    // improve the silhouette while retaining local contact-patch deformation.
    return 0.5 * ((2.0 * b) + (c - a) * t +
        (2.0 * a - 5.0 * b + 4.0 * c - d) * t * t +
        (-a + 3.0 * b - 3.0 * c + d) * t * t * t);
}
vec3 wheel_skin(int hub, vec3 p) {
    int w = (hub - 16) / 21;
    vec3 center = mix(ring_centers[w * 2], ring_centers[w * 2 + 1], p.y);
    vec3 ring = mix(ring_sample(hub + 1, p.x), ring_sample(hub + 11, p.x), p.y);
    vec3 radial = ring - center;
    float pad = tire_padding * clamp((p.z - 0.50) * 2.0, 0.0, 1.0);
    return center + radial * p.z + normalize(radial + vec3(0.000001)) * pad;
}
void vertex() {
    bind_position = VERTEX;
    int binding = int(round(UV2.x));
    vec3 point;
    if (binding < 16) {
        point = box_skin(binding, VERTEX);
        NORMAL = box_normal(binding, VERTEX, NORMAL);
    } else if (binding >= 100) {
        int wheel = (binding - 100) % 4;
        vec3 upper = node_positions[wheel + (binding < 104 ? 4 : 0)];
        vec3 lower = node_positions[16 + wheel * 21];
        vec3 axis = normalize(lower - upper);
        vec3 forward = normalize(node_positions[0] - node_positions[2]);
        vec3 side = normalize(cross(axis, forward));
        vec3 other = normalize(cross(axis, side));
        point = mix(upper, lower, VERTEX.x) + side * VERTEX.y + other * VERTEX.z;
        NORMAL = normalize(axis * NORMAL.x + side * NORMAL.y + other * NORMAL.z);
    } else {
        int wheel = (binding - 16) / 21;
        vec3 axle = normalize(ring_centers[wheel * 2 + 1] - ring_centers[wheel * 2]);
        vec3 center = mix(ring_centers[wheel * 2], ring_centers[wheel * 2 + 1], VERTEX.y);
        point = wheel_skin(binding, VERTEX);
        vec3 radial = normalize(point - center + vec3(0.000001));
        vec3 tangent = normalize(cross(axle, radial));
        NORMAL = normalize(tangent * NORMAL.x + axle * NORMAL.y + radial * NORMAL.z);
    }
    VERTEX = point - rig_center;
}
