#/bin/sh
#this file is a wrapper for the new ffmpeg whisper implementation
#it takes the input file, the model's path
# example ffmpeg -i "/media/pool3p/VIDEO4/movies4/Armageddon (1998)/Armageddon (1998).mp4" -vn -af "whisper=model=/media/disk1/rancherdata/subextract/models/ggml-large-v3-turbo.bin:language=en:queue=3:destination=output.srt:format=srt" -f null -
#first we need to get the directory from the first argument, which is the whole path of the input file
inputfile="$1"
modelpath="$2"
#raise an error if the arguments are not provided
if [ -z "$inputfile" ] || [ -z "$modelpath" ]; then
  echo "Usage: $0 <inputfile> <modelpath>"
  echo example: "$0 '/media/pool4p/Movies6/Hitman (2007)/Hitman (2007).mkv' '/media/disk1/rancherdata/subextract/models/ggml-large-v3-turbo.bin'"
  exit 1
fi

#extract the directory path from the input file path
inputdir=$(dirname "$inputfile")
#extract the filename without extension from the input file path
filename=$(basename "$inputfile")
filename_noext="${filename%.*}"
#it's simpler and more efficient to just change to the input file's directory and use the filename only
cd "$inputdir" || exit 1
#construct the output file path
outputfile="$filename_noext.srt"
#echo the command we're about to run
echo "ffmpeg -i \"$inputfile\" -vn -af \"whisper=model=$modelpath:language=en:queue=5:destination=$outputfile:format=srt\" -f null -"


#run the ffmpeg command with the whisper filter

ffmpeg -i "$inputfile" -vn -af "whisper=model=$modelpath:language=en:queue=5:destination=$outputfile:format=srt" -f null -
