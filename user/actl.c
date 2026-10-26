/* actl - minimal ALSA control get/set for vell amp tuning
 * usage: actl get <name> | actl set <name> <value> [--enum]
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <alsa/asoundlib.h>

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: actl get|set <name> [value] [--enum]\n"); return 2; }
    snd_ctl_t *ctl;
    int rc = snd_ctl_open(&ctl, "hw:0", 0);
    if (rc < 0) { fprintf(stderr, "open: %s\n", snd_strerror(rc)); return 1; }

    snd_ctl_elem_id_t *id;
    snd_ctl_elem_id_alloca(&id);
    snd_ctl_elem_id_set_name(id, argv[2]);
    snd_ctl_elem_id_set_interface(id, SND_CTL_ELEM_IFACE_MIXER);
    snd_ctl_elem_id_set_index(id, 0);

    snd_ctl_elem_info_t *info;
    snd_ctl_elem_info_alloca(&info);
    snd_ctl_elem_info_set_id(info, id);
    rc = snd_ctl_elem_info(ctl, info);
    if (rc < 0) { fprintf(stderr, "info(%s): %s\n", argv[2], snd_strerror(rc)); return 1; }
    const char *type = snd_ctl_elem_info_get_type(info) == SND_CTL_ELEM_TYPE_BOOLEAN ? "bool"
                     : snd_ctl_elem_info_get_type(info) == SND_CTL_ELEM_TYPE_INTEGER ? "int"
                     : snd_ctl_elem_info_get_type(info) == SND_CTL_ELEM_TYPE_ENUMERATED ? "enum" : "other";

    snd_ctl_elem_value_t *val;
    snd_ctl_elem_value_alloca(&val);
    snd_ctl_elem_value_set_id(val, id);

    if (strcmp(argv[1], "get") == 0) {
        rc = snd_ctl_elem_read(ctl, val);
        if (rc < 0) { fprintf(stderr, "read: %s\n", snd_strerror(rc)); return 1; }
        long v = snd_ctl_elem_info_get_type(info) == SND_CTL_ELEM_TYPE_BOOLEAN ? snd_ctl_elem_value_get_boolean(val, 0)
               : snd_ctl_elem_info_get_type(info) == SND_CTL_ELEM_TYPE_INTEGER ? snd_ctl_elem_value_get_integer(val, 0)
               : snd_ctl_elem_value_get_enumerated(val, 0);
        printf("%s %s = %ld\n", argv[2], type, v);
        if (snd_ctl_elem_info_get_type(info) == SND_CTL_ELEM_TYPE_INTEGER)
            printf("  range %ld..%ld\n", snd_ctl_elem_info_get_min(info), snd_ctl_elem_info_get_max(info));
        return 0;
    }
    if (strcmp(argv[1], "set") == 0 && argc >= 4) {
        long v = strtol(argv[3], NULL, 0);
        if (snd_ctl_elem_info_get_type(info) == SND_CTL_ELEM_TYPE_BOOLEAN)
            snd_ctl_elem_value_set_boolean(val, 0, v);
        else if (snd_ctl_elem_info_get_type(info) == SND_CTL_ELEM_TYPE_INTEGER)
            snd_ctl_elem_value_set_integer(val, 0, v);
        else
            snd_ctl_elem_value_set_enumerated(val, 0, v);
        rc = snd_ctl_elem_write(ctl, val);
        if (rc < 0) { fprintf(stderr, "write: %s\n", snd_strerror(rc)); return 1; }
        printf("%s %s <- %ld (%s, rc=%d)\n", argv[2], type, v, rc == 1 ? "changed" : "unchanged", rc);
        return 0;
    }
    if (strcmp(argv[1], "tlv") == 0 && argc >= 4) {
        /* Push a binary blob via the TLV API. SOF bytes controls expect the
         * buffer to BE a snd_ctl_tlv: {numid=cmd, length, sof_abi_hdr, data}.
         * The Waves tuning blobs ship pre-framed exactly like that, so the
         * file is passed through raw; a bare blob gets wrapped with
         * numid=3 (SOF_CTRL_CMD_BINARY). */
        FILE *f = fopen(argv[3], "rb");
        if (!f) { perror(argv[3]); return 1; }
        fseek(f, 0, SEEK_END); long len = ftell(f); fseek(f, 0, SEEK_SET);
        unsigned int *buf = malloc(len + 4);
        if (fread(buf, 1, len, f) != (size_t)len) { fprintf(stderr, "short read\n"); return 1; }
        fclose(f);
        unsigned int *tlv;
        if (len >= 8 && (long)(buf[1] + 8) == len) {
            tlv = buf; /* already framed */
        } else {
            tlv = malloc(len + 8);
            tlv[0] = 3; tlv[1] = (unsigned int)len;
            memcpy(tlv + 2, buf, len); free(buf);
        }
        rc = snd_ctl_elem_tlv_write(ctl, id, tlv);
        if (rc < 0) rc = snd_ctl_elem_tlv_command(ctl, id, tlv);
        if (rc < 0) { fprintf(stderr, "tlv: %s\n", snd_strerror(rc)); return 1; }
        printf("%s tlv <- %s (rc=%d)\n", argv[2], argv[3], rc);
        return 0;
    }
    fprintf(stderr, "usage: actl get|set|tlv <name> [value|file]\n"); return 2;
}
