// Frame/cabin transforms are factored once per update on the CPU. The body
// uses a single continuous rest-space field: a shared edge cannot open merely
// because its adjoining panel used to belong to a different solver cell.
uniform vec3 node_positions[100];
uniform vec3 body_coefficients[16];
uniform vec3 ring_centers[8];
uniform vec3 wheel_axes[4];
uniform vec4 patch_planes[24];
uniform vec4 patch_centers[24];
uniform float wheel_phases[4];
uniform vec3 wheel_up = vec3(0.0, 1.0, 0.0);
uniform vec3 link_starts[14];
uniform vec3 link_ends[14];
uniform vec3 axle_ups[2];
uniform float tire_radius = 0.46;
uniform float tire_width = 0.2668;
uniform vec3 rig_center = vec3(0.0);
uniform vec3 cab_offset = vec3(0.0);
uniform vec3 cab_scale = vec3(1.0);
uniform float body_height = 0.3;
uniform float blend_start = 0.20;
uniform float blend_end = 0.94;
uniform float tire_padding = 0.0552;
varying vec3 bind_position;
varying vec3 bind_normal;

void cell_skin(int b, vec3 p, out vec3 point, out vec3 dx, out vec3 dy, out vec3 dz) {
    vec3 cx = body_coefficients[b + 1];
    vec3 cy = body_coefficients[b + 2];
    vec3 cz = body_coefficients[b + 3];
    vec3 cxy = body_coefficients[b + 4];
    vec3 cxz = body_coefficients[b + 5];
    vec3 cyz = body_coefficients[b + 6];
    vec3 cxyz = body_coefficients[b + 7];
    point = body_coefficients[b] + cx*p.x + cy*p.y + cz*p.z
        + cxy*p.x*p.y + cxz*p.x*p.z + cyz*p.y*p.z + cxyz*p.x*p.y*p.z;
    dx = cx + cxy*p.y + cxz*p.z + cxyz*p.y*p.z;
    dy = cy + cxy*p.x + cyz*p.z + cxyz*p.x*p.z;
    dz = cz + cxz*p.x + cyz*p.y + cxyz*p.x*p.y;
}
void body_skin(vec3 p, vec3 normal, out vec3 point, out vec3 mapped_normal) {
    vec3 f, fx, fy, fz;
    vec3 c, cx, cy, cz;
    cell_skin(0, p, f, fx, fy, fz);
    cell_skin(8, cab_offset + p * cab_scale, c, cx, cy, cz);
    float t = clamp((p.y * body_height - blend_start) / (blend_end - blend_start), 0.0, 1.0);
    float blend = t * t * (3.0 - 2.0*t);
    float derivative = 6.0*t*(1.0-t) * body_height / (blend_end - blend_start);
    point = mix(f, c, blend);
    vec3 dx = mix(fx, cx * cab_scale.x, blend);
    vec3 dy = mix(fy, cy * cab_scale.y, blend) + (c-f)*derivative;
    vec3 dz = mix(fz, cz * cab_scale.z, blend);
    vec3 n = cross(dy, dz)*normal.x + cross(dz, dx)*normal.y + cross(dx, dy)*normal.z;
    mapped_normal = dot(n,n) > 0.00000001 ? normalize(n) : vec3(0.0, 1.0, 0.0);
}
vec3 ring_sample(int first, float phase) {
    float f = fract(phase) * 10.0;
    int k = int(floor(f));
    float t = fract(f);
    vec3 a = node_positions[first + (k + 9) % 10];
    vec3 b = node_positions[first + k];
    vec3 c = node_positions[first + (k + 1) % 10];
    vec3 d = node_positions[first + (k + 2) % 10];
    // Catmull-Rom follows derived wheel-ring guides. Their continuous rotation
    // and small supported-patch squash come from the four physical wheel hubs;
    // these 80 samples are not independent dynamic tire particles.
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
    vec3 point = center + radial * p.z + normalize(radial + vec3(0.000001)) * pad;
    // The bead is clamped to a rigid rim; carcass deflection grows through
    // the sidewall instead of opening a seam at the metal interface.
    if (p.z < 0.85) {
        vec3 axle = wheel_axes[w];
        vec3 up = normalize(wheel_up - axle * dot(wheel_up, axle));
        float angle = p.x * 6.28318530718 + wheel_phases[w];
        vec3 rigid_radial = up * cos(angle) + normalize(cross(axle, up)) * sin(angle);
        vec3 rigid_point = node_positions[hub] + axle * ((p.y - 0.5) * tire_width) + rigid_radial * (tire_radius * 0.88 * p.z);
        point = mix(rigid_point, point, smoothstep(0.51, 0.85, p.z));
    }
    // Native ring guides already carry pressure/load squash, shoulder bulge
    // and traction shear. Clip only the padded rubber against nearby patches.
    if (p.z > 0.55) {
        for (int pass = 0; pass < 2; pass++) {
            for (int j = 0; j < 6; j++) {
                vec4 plane = patch_planes[w * 6 + j];
                vec4 patch = patch_centers[w * 6 + j];
                if (dot(plane.xyz, plane.xyz) < 0.5 || patch.w <= 0.0) continue;
                vec3 delta = point - patch.xyz;
                vec3 tangent = delta - plane.xyz * dot(delta, plane.xyz);
                if (dot(tangent, tangent) <= patch.w * patch.w) {
                    point += plane.xyz * max(0.0, 0.002 - (dot(point, plane.xyz) - plane.w));
                }
            }
        }
    }
    return point;
}
void vertex() {
    bind_position = VERTEX;
    bind_normal = NORMAL;
    int binding = int(round(UV2.x));
    vec3 point;
    if (binding < 16) {
        vec3 mapped_normal;
        body_skin(VERTEX, NORMAL, point, mapped_normal);
        NORMAL = mapped_normal;
    } else if (binding >= 200) {
        int w = binding - 200;
        vec3 axle = wheel_axes[w];
        vec3 up = wheel_up;
        up = normalize(up - axle * dot(up, axle));
        float angle = VERTEX.x * 6.28318530718 + wheel_phases[w];
        vec3 radial = up * cos(angle) + normalize(cross(axle, up)) * sin(angle);
        point = node_positions[16 + w * 21] + axle * ((VERTEX.y - 0.5) * tire_width) + radial * (tire_radius * 0.88 * VERTEX.z);
        NORMAL = normalize(cross(axle, radial) * NORMAL.x + axle * NORMAL.y + radial * NORMAL.z);
    } else if (binding >= 100) {
        int wheel = (binding - 100) % 4;
        vec3 upper = link_starts[8 + wheel];
        vec3 lower = link_ends[8 + wheel];
        if (binding >= 114) {
            upper = link_starts[binding - 102];
            lower = link_ends[binding - 102];
        } else if (binding >= 110) {
            upper = link_starts[binding - 106];
            lower = link_ends[binding - 106];
        } else if (binding >= 104 && binding < 108) {
            upper = link_starts[binding - 104];
            lower = link_ends[binding - 104];
        } else if (binding >= 108) {
            int axle = binding - 108;
            upper = node_positions[16 + axle * 42];
            lower = node_positions[37 + axle * 42];
        }
        vec3 axis = normalize(lower - upper);
        vec3 reference = abs(axis.y) < 0.90 ? vec3(0.0, 1.0, 0.0) : vec3(0.0, 0.0, 1.0);
        if (binding == 108 || binding == 109) reference = axle_ups[binding - 108];
        vec3 side = normalize(cross(axis, reference));
        vec3 other = normalize(cross(axis, side));
        point = mix(upper, lower, VERTEX.x) + side * VERTEX.y + other * VERTEX.z;
        NORMAL = normalize(axis * NORMAL.x + side * NORMAL.y + other * NORMAL.z);
    } else {
        int wheel = (binding - 16) / 21;
        vec3 axle = normalize(ring_centers[wheel * 2 + 1] - ring_centers[wheel * 2]);
        vec3 center = mix(ring_centers[wheel * 2], ring_centers[wheel * 2 + 1], VERTEX.y);
        point = wheel_skin(binding, VERTEX);
        vec3 radial = normalize(point - center + vec3(0.000001));
        // A loaded footprint has a flattened surface normal as well as a
        // flattened silhouette; preserve sidewall and individual lug normals.
        for (int j = 0; j < 6; j++) {
            vec4 plane = patch_planes[wheel * 6 + j];
            vec4 patch = patch_centers[wheel * 6 + j];
            if (dot(plane.xyz, plane.xyz) < 0.5 || patch.w <= 0.0) continue;
            vec3 delta = point - patch.xyz;
            vec3 along = delta - plane.xyz * dot(delta, plane.xyz);
            float depth = dot(point, plane.xyz) - plane.w;
            if (dot(along, along) < patch.w * patch.w && dot(radial, -plane.xyz) > 0.65) {
                float flatten_weight = (1.0 - smoothstep(0.002, 0.045, depth)) * 0.85;
                radial = normalize(mix(radial, -plane.xyz, flatten_weight));
            }
        }
        vec3 tangent = normalize(cross(axle, radial));
        NORMAL = normalize(tangent * NORMAL.x + axle * NORMAL.y + radial * NORMAL.z);
    }
    VERTEX = point - rig_center;
}
