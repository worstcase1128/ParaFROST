#!/bin/bash

ch='|'
lineWidth=90
rulerStr="------------------------------------------------------------------------------------"
logfile=install.log
cputemplate=templates/makefile.cpu
gputemplate=templates/makefile.gpu
binary=parafrost
library=lib${binary}.a

echo -n > $logfile

# functions
usage () {
cat << EOF
$ch usage: install [ <option> ... ]
$ch 
$ch where '<option>' is one of the following
$ch
$ch	-h or --help          print this usage summary
$ch	-c or --cpu           install CPU solver
$ch	-g or --gpu           install GPU solver (if CUDA exists)
$ch	-w or --wall          compile with '-Wall' flag
$ch	-d or --debug         compile with debugging inf|ormation
$ch	-t or --assert        enable only code assertions
$ch	-p or --pedantic      compile with '-pedantic' flag
$ch	-l or --logging       enable logging (needed for verbosity level > 2)
$ch	-s or --statistics    enable costly statistics (may impact runtime)
$ch	-a or --all           enable all above flags except 'assert'
$ch	--clean=<target>      remove old installation of <cpu | gpu | all> solvers
$ch	--standard=<n>        compile with <11 | 14 | 17 > c++ standard
$ch	--extra="flags"       pass extra "flags" to the compiler(s)
$ch$rulerStr
EOF
exit 0
}

pfbanner () {
printf "+%${lineWidth}s+\n" |tr ' ' '-'
printf "$ch %-$((lineWidth - 1))s$ch\n"  \
"                    ParaFROST solver installer (use -h for options)"
printf "+%${lineWidth}s+\n" |tr ' ' '-'
}

pffinal () {
log ""
log "check '$1' directory for '$binary' and its library '$library'" 
printf "+%${lineWidth}s+\n" |tr ' ' '-'
}

ruler () {
echo -n $ch
printf "%${lineWidth}s+\n" |tr ' ' '-'
echo -n $ch >> $logfile
printf "%${lineWidth}s+\n" |tr ' ' '-' >> $logfile
}

log () {
printf "$ch %-$((lineWidth - 1))s\n" "$1"
echo printf "$ch %-$((lineWidth - 1))s\n" "$1" >> $logfile
}

logn () {
printf "$ch %s" "$1"
echo printf "$ch %s" "$1" >> $logfile
}

endline () {
echo "done."
echo "done." >> $logfile
}

error () {
log "$prefix error: $*"
ruler
exit 1
}

# banner
pfbanner

# operating system
HOST_OS=$(uname -srmn 2>/dev/null | tr "[:upper:]" "[:lower:]")
[ -z "$HOST_OS" ] && error "cannot communicate with the operating system"

# host compiler
HOST_COMPILER=g++

# compiler version
compilerVer=$(g++ --version | sed -n '1p')
compilerVer=$(echo $compilerVer|tr -d '\n')
compilerVer=$(echo $compilerVer|tr -d '\r')
[ -z "$compilerVer" ] && error "cannot read the compiler version"

# target arch
TARGET_ARCH=$(uname -m)
[ -z "$TARGET_ARCH" ] && error "cannot read the system architecture"

# target size
TARGET_SIZE=$(getconf LONG_BIT)
[ -z "$TARGET_SIZE" ] && error "cannot read the architecture bit-size"

# time
now=$(date)
[ -z "$now" ] && error "cannot read the system date"

#---------
# options
#---------
all=0
wall=1
icpu=0
igpu=0
debug=0
extra=""
clean=""
assert=0
logging=0
pedantic=0
standard=17
statistics=0

while [ $# -gt 0 ]
do
  case $1 in

    -h|--help) usage;;
		
	-w|--wall) wall=1;;
    -d|--debug) debug=1;;
    -t|--assert) assert=1;;
	-n|--nopedantic) pedantic=0;;
	
    -l|--logging) logging=1;;
	-s|--statistics) statistics=1;;

	-c|--cpu) icpu=1;;
	-g|--gpu) igpu=1;;

	-a|--all) all=1;;

	--clean=*)
	  clean="${1#*=}"
      ;;

    --standard=*)
      standard="${1#*=}"
      ;;

    --extra=*)
      extra="${1#*=}"
      ;;

    *) error "invalid option '$1' (use '-h' for help)";;

  esac
  shift
done

if [ $debug = 1 ] && [ $assert = 1 ]; then error "cannot combine 'assert' and 'debug' modes"; fi

if [[ "$clean" != "" ]] && [[ "$clean" != "cpu" ]] && [[ "$clean" != "gpu" ]] && [[ "$clean" != "all" ]]; then 
	error "invalid clean target '$clean'"
fi

if [ ! $standard = 11 ] && [ ! $standard = 14 ] && [ ! $standard = 17 ]; then 
	error "invalid c++ standard '$standard'"
fi

if [ $all = 1 ]; then wall=1;debug=1;assert=0;pedantic=1;logging=1;statistics=1; fi

# cleaning
cleanCPU=0
cleanGPU=0
if [[ "$clean" = "cpu" ]] || [[ "$clean" = "all" ]]; then 
	cleanCPU=1
	logn "cleaning up CPU files (other options will be ignored).."
	rm -rf build/cpu
	rm -f Makefile
	srcdir=src/cpu
	rm -f $srcdir/Makefile
	rm -f $srcdir/*.o $srcdir/$binary $srcdir/$library
	endline
	ruler
fi
if [[ "$clean" = "gpu" ]] || [[ "$clean" = "all" ]]; then 
	cleanGPU=1
	logn "cleaning up GPU files (other options will be ignored).."
	rm -rf build/gpu
	rm -f Makefile
	srcdir=src/gpu
	rm -f $srcdir/Makefile
	rm -f $srcdir/*.o $srcdir/*.cuo $srcdir/$binary $srcdir/$library
	endline
	ruler
fi
[ $cleanCPU = 1 ] || [ $cleanGPU = 1 ] && exit 0

#---------------------------
# start building CPU solver
#---------------------------

if [ $icpu = 1 ]; then # start of CPU installation block

srcdir=src/cpu
builddir=build/cpu
makefile=$srcdir/Makefile

# default flags
OPTIMIZE="-O3"
FASTMATH="-use_fast_math"
ARCH="-m${TARGET_SIZE}"
STD="-std=c++$standard"

log "installing ParaFROST-CPU on '$now'"
log " under operating system '$HOST_OS'"
log " with a '$compilerVer' compiler"
log ""
logn "creating '$HOST_COMPILER' flags.."

if [ $debug = 0 ] && [ $assert = 0 ]; then 
	CCFLAGS="$CCFLAGS -DNDEBUG $OPTIMIZE $FASTMATH"
elif [ $debug = 1 ]; then
	CCFLAGS="$CCFLAGS -g"
elif [ $assert = 1 ]; then 
	CCFLAGS="$CCFLAGS $OPTIMIZE"
fi
if [[ "$HOST_OS" == *"cygwin"* ]]; then pedantic=0; fi
[ $wall = 1 ] && CCFLAGS="$CCFLAGS -Wall"
[ $pedantic = 1 ] && CCFLAGS="$CCFLAGS -pedantic"
[ $logging = 1 ] && CCFLAGS="$CCFLAGS -DLOGGING"
[ $statistics = 1 ] && CCFLAGS="$CCFLAGS -DSTATISTICS"

CCFLAGS="$ARCH $STD$CCFLAGS"

if [[ $extra != "" ]]; then CCFLAGS="$CCFLAGS $extra"; fi

endline

# building

log ""
log "building with:"
log ""
log "'$CCFLAGS'"
log ""

[ ! -d $srcdir ] && error "cannot find sources directory"

# generate version header file
buildfile=$srcdir/version.h
versionsrc=$srcdir/version.in
[ ! -f $versionsrc ] && error "cannot find '$versionsrc' template file"
[ -f $buildfile ] && rm $buildfile

cp $versionsrc $buildfile

logn "generating header '$buildfile' from 'version.in'.."

version=unknown
[ -f VERSION ] && version=$(head -n 1 VERSION)
[ ! -z "$version" ] && echo "#define VERSION \"$version\"" >> $buildfile
echo "#define COMPILER \"$compilerVer\"" >> $buildfile
echo "#define OSYSTEM \"$HOST_OS\"" >> $buildfile
echo "#define DATE \"$now\"" >> $buildfile

endline

[ ! -f $cputemplate ] && error "cannot find the CPU makefile template"

cp $cputemplate $makefile
sed -i "s|^CCFLAGS.*|CCFLAGS := $CCFLAGS|" $makefile
sed -i "s/^BIN.*/BIN := $binary/" $makefile
sed -i "s/^LIB.*/LIB := $library/" $makefile

log ""

mkdir -p $builddir

cd $srcdir
make
cd ../../

if [ ! -f $srcdir/$binary ] || [ ! -f $srcdir/$library ]; then
	log ""
	log "could not install the solver due to previous errors"
	error "check 'install.log' for more information"
fi
mv $srcdir/$binary $builddir
mv $srcdir/$library $builddir

pffinal $builddir

fi # end of CPU installation block

#---------------------------
# start building GPU solver
#---------------------------

if [ $igpu = 1 ]; then # start of GPU installation block

if [[ "$HOST_OS" == *"cygwin"* ]]; then error "cygwin not supported to install the GPU solver, use VS C++ instead"; fi

CUDA_DIR=/usr/local/cuda
[ ! -d "$CUDA_DIR" ] && error "no cuda toolkit installed"
NVCC=$CUDA_DIR/bin/nvcc

# nvcc compiler version
NVCCVER=$($NVCC --version | sed -n '4p')
NVCCVER=$(echo $NVCCVER|tr -d '\n')
NVCCVER=$(echo $NVCCVER|tr -d '\r')
[ -z "$NVCCVER" ] && error "cannot read the compiler version"
NVCCVERSHORT=$(echo $NVCCVER | cut -d "V" -f2)
NVCCVER="nvcc $NVCCVERSHORT"

srcdir=src/gpu
builddir=build/gpu
makefile=$srcdir/Makefile

log "installing ParaFROST-GPU on '$now'"
log " under operating system '$HOST_OS'"
log " with $compilerVer and $NVCCVER compilers"
log ""
log "creating '$NVCC + $HOST_COMPILER' flags.."

if [[ $pedantic = 1 ]]; then log "  turning off 'pedantic' due to incompatibility with Thrust"; pedantic=0; fi
if [[ $standard > 14 ]]; then log "  falling back to 'c++14' standard due to incompatibility with Thrust"; standard=14; fi

# default flags
OPTIMIZE="-O3"
FASTMATH="-use_fast_math"
ARCH="-m${TARGET_SIZE}"
STD="-std=c++$standard"
CCFLAGS="$STD"

if [ $debug = 0 ] && [ $assert = 0 ]; then 
	NVCCFLAGS="$NVCCFLAGS -DNDEBUG $OPTIMIZE $FASTMATH"
elif [ $debug = 1 ]; then
	NVCCFLAGS="$NVCCFLAGS -g"
elif [ $assert = 1 ]; then 
	NVCCFLAGS="$NVCCFLAGS $OPTIMIZE"
fi
[ $wall = 1 ] && CCFLAGS="$CCFLAGS -Wall"
[ $pedantic = 1 ] && CCFLAGS="$CCFLAGS -pedantic"
[ $logging = 1 ] && NVCCFLAGS="$NVCCFLAGS -DLOGGING"
[ $statistics = 1 ] && NVCCFLAGS="$NVCCFLAGS -DSTATISTICS"

NVCCFLAGS="$ARCH$NVCCFLAGS"

if [[ $extra != "" ]]; then CCFLAGS="$CCFLAGS $extra"; fi

# building

log ""
log "building with:"
log ""
log "'$NVCCFLAGS $CCFLAGS'"
log ""

[ ! -d $srcdir ] && error "cannot find sources directory"

# generate version header file
buildfile=$srcdir/version.h
versionsrc=$srcdir/version.in
[ ! -f $versionsrc ] && error "cannot find '$versionsrc' template file"
[ -f $buildfile ] && rm $buildfile

cp $versionsrc $buildfile

logn "generating header '$buildfile' from 'version.in'.."

version=unknown
[ -f VERSION ] && version=$(head -n 1 VERSION)
[ ! -z "$version" ] && echo "#define VERSION \"$version\"" >> $buildfile
echo "#define COMPILER \"$compilerVer + $NVCCVER\"" >> $buildfile
echo "#define OSYSTEM \"$HOST_OS\"" >> $buildfile
echo "#define DATE \"$now\"" >> $buildfile

endline

[ ! -f $gputemplate ] && error "cannot find the GPU makefile template"

cp $gputemplate $makefile
sed -i "s|^CUDA_PATH.*|CUDA_PATH := $CUDA_DIR|" $makefile
sed -i "s|^NVCCFLAGS.*|NVCCFLAGS := $NVCCFLAGS|" $makefile
sed -i "s|^CCFLAGS.*|CCFLAGS := $CCFLAGS|" $makefile
sed -i "s/^BIN :=.*/BIN := $binary/" $makefile
sed -i "s/^LIB :=.*/LIB := $library/" $makefile

log ""

mkdir -p $builddir

cd $srcdir
make
cd ../../

if [ ! -f $srcdir/$binary ] || [ ! -f $srcdir/$library ]; then
	log ""
	log "could not install the solver due to previous errors"
	error "check 'install.log' for more information"
fi
mv $srcdir/$binary $builddir
mv $srcdir/$library $builddir

pffinal $builddir

fi # end of GPU installation block