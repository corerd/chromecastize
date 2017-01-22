#!/bin/bash

# Check only if input files are eligible to be chromecastized

##########
# CONFIG #
##########
HOME=~/.chromecastize
SUPPORTED_EXTENSIONS=('mkv' 'avi' 'mp4' '3gp' 'mov' 'mpg' 'mpeg' 'qt' 'wmv' 'm2ts' 'flv')

SUPPORTED_GFORMATS=('MPEG-4' 'Matroska')
UNSUPPORTED_GFORMATS=('BDAV' 'AVI' 'Flash Video')

SUPPORTED_VCODECS=('AVC')
UNSUPPORTED_VCODECS=('MPEG-4 Visual' 'xvid' 'MPEG Video', 'HEVC')

SUPPORTED_ACODECS=('AAC' 'MPEG Audio' 'Vorbis' 'Ogg' 'Opus')
UNSUPPORTED_ACODECS=('AC-3' 'DTS' 'PCM')

DEFAULT_VCODEC=h264
DEFAULT_ACODEC=libvorbis
DEFAULT_GFORMAT=mkv

#############
# FUNCTIONS #
#############

# Check if a value exists in an array
# @param $1 mixed  Needle
# @param $2 array  Haystack
# @return  Success (0) if value exists, Failure (1) otherwise
# Usage: in_array "$needle" "${haystack[@]}"
# See: http://fvue.nl/wiki/Bash:_Check_if_array_element_exists
in_array() {
	local hay needle=$1
	shift
	for hay; do
		[[ $hay == $needle ]] && return 0
	done
	return 1
}

# Embed realpath() function.
# `realpath` is a bash command line utility
# that is included in most UNIX distributions but not macOS.
# In macOS is available `grealpath`,
# but it requires installing Homebrew that you you might not want.
# This is a quick and dirty replacement taken from http://stackoverflow.com/a/3572105
# This prints the path verbatim if it begins with a /.
# If not it must be a relative path, so it prepends $PWD to the front.
# The #./ part strips off ./ from the front of $1.
realpath() {
    [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

print_help() {
	echo "Usage: chromecastcheck.sh [ --mp4 | --mkv ] <videofile1> [ videofile2 ... ]"
}

unknown_codec() {
	echo "'$1' is an unknown codec. Please add it to the list in a CONFIG section."
}

is_supported_gformat() {
	if in_array "$1" "${SUPPORTED_GFORMATS[@]}"; then
		return 0
	elif in_array "$1" "${UNSUPPORTED_GFORMATS[@]}"; then
		return 1
	else
		unknown_codec "$1"
		exit 1
	fi
}

is_supported_vcodec() {
	if in_array "$1" "${SUPPORTED_VCODECS[@]}"; then
		return 0
	elif in_array "$1" "${UNSUPPORTED_VCODECS[@]}"; then
		return 1
	else
		unknown_codec "$1"
		exit 1
	fi
}

is_supported_acodec() {
	if in_array "$1" "${SUPPORTED_ACODECS[@]}"; then
		return 0
	elif in_array "$1" "${UNSUPPORTED_ACODECS[@]}"; then
		return 1
	else
		unknown_codec "$1"
		exit 1
	fi
}

is_supported_ext() {
	EXT=`echo $1 | tr '[:upper:]' '[:lower:]'`
	in_array "$EXT" "${SUPPORTED_EXTENSIONS[@]}"
}

mark_as_good() {
	# add file as successfully converted
	echo `$REALPATH "$1"` >> $HOME/processed_files
}

on_success() {
	echo ""
	FILENAME="$1"
	BASENAME=`basename "$FILENAME"`
	echo "- conversion succeeded; file '$FILENAME.$OUTPUT_GFORMAT' saved"
	mark_as_good "$FILENAME.$OUTPUT_GFORMAT"
	echo "- renaming original file as '$FILENAME.bak'"
	mv "$FILENAME" "$FILENAME.bak"
}

on_failure() {
	echo ""
	FILENAME="$1"
	echo "- failed to convert '$FILENAME' (or conversion has been interrupted)"
	echo "- deleting partially converted file..."
	rm "$FILENAME.$OUTPUT_GFORMAT" &> /dev/null
}

process_file() {
	local FILENAME="$1"

	echo "==========="
	echo "Processing: $FILENAME"

	# test extension
	BASENAME=$(basename "$FILENAME")
	EXTENSION="${BASENAME##*.}"
	if ! is_supported_ext "$EXTENSION"; then
		echo "- not a video format, skipping"
		return
	fi

	# test if it's an `chromecastize` generated file
	if grep -Fxq "`$REALPATH "$FILENAME"`" $HOME/processed_files; then
		echo '- file was generated by `chromecastize`, skipping'
		return
	fi

	# test general format
	INPUT_GFORMAT=`mediainfo --Inform="General;%Format%\n" "$FILENAME" | head -n1`
	if is_supported_gformat "$INPUT_GFORMAT" && [ "$OVERRIDE_GFORMAT" = "" ] || [ "$OVERRIDE_GFORMAT" = "$EXTENSION" ]; then
		OUTPUT_GFORMAT="ok"
	else
		# if override format is specified, use it; otherwise fall back to default format
		OUTPUT_GFORMAT="${OVERRIDE_GFORMAT:-$DEFAULT_GFORMAT}"
	fi
	echo "- general: $INPUT_GFORMAT -> $OUTPUT_GFORMAT"

	# test video codec
	INPUT_VCODEC=`mediainfo --Inform="Video;%Format%\n" "$FILENAME" | head -n1`
	if is_supported_vcodec "$INPUT_VCODEC"; then
		OUTPUT_VCODEC="copy"
	else
		OUTPUT_VCODEC="$DEFAULT_VCODEC"
	fi
	echo "- video: $INPUT_VCODEC -> $OUTPUT_VCODEC"

	# test audio codec
	INPUT_ACODEC=`mediainfo --Inform="Audio;%Format%\n" "$FILENAME" | head -n1`
	if is_supported_acodec "$INPUT_ACODEC"; then
		OUTPUT_ACODEC="copy"
	else
		OUTPUT_ACODEC="$DEFAULT_ACODEC"
	fi
	echo "- audio: $INPUT_ACODEC -> $OUTPUT_ACODEC"

	if [ "$OUTPUT_VCODEC" = "copy" ] && [ "$OUTPUT_ACODEC" = "copy" ] && [ "$OUTPUT_GFORMAT" = "ok" ]; then
		echo "- file should be playable by Chromecast!"
		mark_as_good "$FILENAME"
	else
		echo "- video length: `mediainfo --Inform="General;%Duration/String3%" "$FILENAME"`"
		if [ "$OUTPUT_GFORMAT" = "ok" ]; then
			OUTPUT_GFORMAT=$EXTENSION
		fi
		#$FFMPEG -loglevel error -stats -i "$FILENAME" -map 0 -scodec copy -vcodec "$OUTPUT_VCODEC" -acodec "$OUTPUT_ACODEC" "$FILENAME.$OUTPUT_GFORMAT" && on_success "$FILENAME" || on_failure "$FILENAME"
      echo "- file should be *chromecastized*!"
		echo ""
	fi
}

################
# MAIN PROGRAM #
################

# test if `mediainfo` is available
MEDIAINFO=`which mediainfo 2> /dev/null`
if [ -z $MEDIAINFO ]; then
	echo '`mediainfo` is not available, please install it'
	exit 1
fi

# test if `ffmpeg` is available
#FFMPEG=`which avconv 2> /dev/null || which ffmpeg 2> /dev/null`
#if [ -z $FFMPEG ]; then
#	echo '`avconv` (or `ffmpeg`) is not available, please install it'
#	exit 1
#fi

# Use embedded realpath() function.
REALPATH="realpath"

# check number of arguments
if [ $# -lt 1 ]; then
	print_help
	exit 1
fi

# ensure that processed_files file exists
mkdir -p $HOME
touch $HOME/processed_files

for FILENAME in "$@"; do
	if [ "$FILENAME" = "--mp4" ] || [ "$FILENAME" = "--mkv" ]; then
		OVERRIDE_GFORMAT=`echo "$FILENAME" | sed 's/^--//'`
	elif ! [ -e "$FILENAME" ]; then
		echo "File not found ($FILENAME). Skipping..."
	elif [ -d "$FILENAME" ]; then
		ORIG_IFS=$IFS
		IFS=$(echo -en "\n\b")
		for F in $(find "$FILENAME" -type f); do
			process_file $F
		done
		IFS=$ORIG_IFS
	elif [ -f "$FILENAME" ]; then
		process_file "$FILENAME"
	else
		echo "Invalid file ($FILENAME). Skipping..."
	fi
done
