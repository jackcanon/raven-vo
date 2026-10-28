/* Raven VO's raw-PCM driver for unmodified Xiph RNNoise. MIT, Jack Blair. */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
#include "rnnoise.h"
static int write_frame(FILE *out, float *x, size_t n) {
    int16_t pcm[480];
    for (size_t i=0;i<n;i++) pcm[i]=(int16_t)lrintf(fmaxf(-32768.f,fminf(32767.f,x[i])));
    return fwrite(pcm,sizeof(int16_t),n,out)==n;
}
int main(int argc,char **argv) {
    if(argc!=3 || rnnoise_get_frame_size()!=480) return 2;
    FILE *in=fopen(argv[1],"rb"); if(!in)return 3;
    FILE *out=fopen(argv[2],"wb"); if(!out){fclose(in);return 4;}
    DenoiseState *state=rnnoise_create(NULL); if(!state){fclose(in);fclose(out);return 5;}
    int16_t pcm[480]; float frame[480]; size_t previous=0; int ok=1;
    for(;;){
        size_t count=fread(pcm,sizeof(int16_t),480,in); if(!count)break;
        for(size_t i=0;i<480;i++)frame[i]=i<count?pcm[i]:0;
        rnnoise_process_frame(state,frame,frame);
        if(previous && !write_frame(out,frame,previous)){ok=0;break;}
        previous=count;
    }
    if(ok && previous){memset(frame,0,sizeof(frame));rnnoise_process_frame(state,frame,frame);ok=write_frame(out,frame,previous);}
    if(ferror(in))ok=0;
    rnnoise_destroy(state);fclose(in);if(fclose(out))ok=0;return ok?0:6;
}
