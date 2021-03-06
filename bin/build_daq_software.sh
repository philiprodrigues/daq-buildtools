#!/bin/bash

HERE=$(cd $(dirname $(readlink -f ${BASH_SOURCE})) && pwd)

# Import find_work_area function
source ${DBT_ROOT}/scripts/setup_tools.sh

BASEDIR=$(find_work_area)
if [[ -z $BASEDIR ]]; then
    echo -e "${COL_RED} DBT Work aread directory not found; exiting...${COL_NULL}" >&2
    exit 1
fi

BUILDDIR=${BASEDIR}/build
LOGDIR=${BASEDIR}/log
SRCDIR=${BASEDIR}/sourcecode
#########################################################################################

run_tests=false
clean_build=false 
verbose=false
pkgname_specified=false
perform_install=false
lint=false

for arg in "$@" ; do
  if [[ "$arg" == "--help" ]]; then
    echo "Usage: "./$( basename $0 )" --clean --unittest --lint --install --verbose --help "
    echo
    echo " --clean means the contents of ./build are deleted and CMake's config+generate+build stages are run"
    echo " --unittest means that unit test executables found in ./build/*/unittest are all run"
    echo " --lint means you check for deviations from the DUNE style guide, https://github.com/DUNE-DAQ/styleguide/blob/develop/dune-daq-cppguide.md" 
    echo " --install means that you want the code from your package(s) installed in the directory which was pointed to by the DBT_INSTALL_DIR environment variable before the most recent clean build"
    echo " --verbose means that you want verbose output from the compiler"

    echo
    echo "All arguments are optional. With no arguments, CMake will typically just run "
    echo "build, unless build/CMakeCache.txt is missing"
    echo
    exit 0    

  elif [[ "$arg" == "--clean" ]]; then
    clean_build=true
  elif [[ "$arg" == "--unittest" ]]; then
    run_tests=true
  elif [[ "$arg" == "--lint" ]]; then
    lint=true
  elif [[ "$arg" == "--verbose" ]]; then
    verbose=true
  elif [[ "$arg" == "--pkgname" ]]; then
    echo "Use of --pkgname is deprecated; run with \" --help\" to see valid options. Exiting..." >&2
    exit 1
  elif [[ "$arg" == "--install" ]]; then
    perform_install=true
  else
    echo "Unknown argument provided; run with \" --help\" to see valid options. Exiting..." >&2
    exit 1
  fi
done

if [[ -z $DBT_SETUP_BUILD_ENVIRONMENT_SCRIPT_SOURCED ]]; then
echo
echo "It appears you haven't yet executed \"setup_build_environment\"; please source it before running this script. Exiting..."
echo
exit 2
fi

if [[ ! -d $BUILDDIR ]]; then
    echo "Expected build directory $BUILDDIR not found; exiting..." >&2
    exit 1
fi

cd $BUILDDIR

if $clean_build; then 
  
   # Want to be damn sure of we're in the right directory, rm -rf * is no joke...

   if  [[ $( echo $PWD | sed -r 's!.*/(.*)!\1!' ) =~ ^build/*$ ]]; then
     echo "Clean build requested, will delete all the contents of build directory \"$PWD\"."
     echo "If you wish to abort, you have 5 seconds to hit Ctrl-c"
     sleep 5
     rm -rf *
   else
     echo "SCRIPT ERROR: you requested a clean build, but this script thinks that $BUILDDIR isn't the build directory." >&2
     echo "Please contact John Freeman at jcfree@fnal.gov and notify him of this message" >&2
     exit 10
   fi

fi


build_log=$LOGDIR/build_attempt_$( date | sed -r 's/[: ]+/_/g' ).log

if [[ -n $( which unbuffer ) ]]; then
  UB_CMAKE="unbuffer cmake"
else
  UB_CMAKE="cmake"
fi

# We usually only need to explicitly run the CMake configure+generate
# makefiles stages when it hasn't already been successfully run;
# otherwise we can skip to the compilation. We use the existence of
# CMakeCache.txt to tell us whether this has happened; notice that it
# gets renamed if it's produced but there's a failure.

if ! [ -e CMakeCache.txt ];then

generator_arg=
if [ "x${SETUP_NINJA}" != "x" ]; then
  generator_arg="-G Ninja"
fi


starttime_cfggen_d=$( date )
starttime_cfggen_s=$( date +%s )

${UB_CMAKE} -DMOO_CMD=$(which moo) -DDBT_ROOT=${DBT_ROOT} -DCMAKE_INSTALL_PREFIX=$DBT_INSTALL_DIR ${generator_arg} $SRCDIR |& tee $build_log

retval=${PIPESTATUS[0]}  # Captures the return value of cmake, not tee
endtime_cfggen_d=$( date )
endtime_cfggen_s=$( date +%s )

if [[ "$retval" == "0" ]]; then

sed -i -r '1 i\# If you want to add or edit a variable, be aware that the config+generate stage is skipped in $build_script if this file exists' $BUILDDIR/CMakeCache.txt
sed -i -r '2 i\# Consider setting variables you want cached with the CACHE option in the relevant CMakeLists.txt file instead' $BUILDDIR/CMakeCache.txt

cfggentime=$(( endtime_cfggen_s - starttime_cfggen_s ))
echo "CMake's config+generate stages took $cfggentime seconds"
echo "Start time: $starttime_cfggen_d"
echo "End time:   $endtime_cfggen_d"

else

mv -f CMakeCache.txt CMakeCache.txt.most_recent_failure

echo
echo "There was a problem running \"cmake $SRCDIR\" from $BUILDDIR (i.e.," >&2
echo "CMake's config+generate stages). Scroll up for" >&2
echo "details or look at ${build_log}. Exiting..."
echo

    exit 30
fi

else

echo "The config+generate stage was skipped as CMakeCache.txt was already found in $BUILDDIR"

fi # !-e CMakeCache.txt

nprocs=$( grep -E "^processor\s*:\s*[0-9]+" /proc/cpuinfo  | wc -l )
nprocs_argument=""
 
if [[ -n $nprocs && $nprocs =~ ^[0-9]+$ ]]; then
    echo "This script believes you have $nprocs processors available on this system, and will use as many of them as it can"
    nprocs_argument=" -j $nprocs"
else
    echo "Unable to determine the number of processors available, will not pass the \"-j <nprocs>\" argument on to the build stage" >&2
fi




starttime_build_d=$( date )
starttime_build_s=$( date +%s )

build_options=""
if $verbose; then
  build_options=" --verbose"
fi

${UB_CMAKE} --build . $build_options -- $nprocs_argument |& tee -a $build_log

retval=${PIPESTATUS[0]}  # Captures the return value of cmake --build, not tee
endtime_build_d=$( date )
endtime_build_s=$( date +%s )

if [[ "$retval" == "0" ]]; then

buildtime=$((endtime_build_s - starttime_build_s))

else

echo
echo "There was a problem running \"cmake --build .\" from $BUILDDIR (i.e.," >&2
echo "CMake's build stage). Scroll up for" >&2
echo "details or look at the build log via \"more ${build_log}\". Exiting..."
echo

   exit 40
fi

num_estimated_warnings=$( grep "warning: " ${build_log} | wc -l )

echo

if [[ -n $cfggentime ]]; then
  echo
  echo "config+generate stage took $cfggentime seconds"
  echo "Start time: $starttime_cfggen_d"
  echo "End time:   $endtime_cfggen_d"
  echo
else
  echo "config+generate stage was skipped"
fi
echo "build stage took $buildtime seconds"
echo "Start time: $starttime_build_d"
echo "End time:   $endtime_build_d"
echo
echo "Output of build contains an estimated $num_estimated_warnings warnings, and can be viewed later via: "
echo "\"more ${build_log}\""
echo

if [[ -n $cfggentime ]]; then
  echo "CMake's config+generate+build stages all completed successfully"
  echo
else
  echo "CMake's build stage completed successfully"
fi

if $perform_install ; then
  cd $BUILDDIR

  cmake --build . --target install -- -j $nprocs
 
  if [[ "$?" == "0" ]]; then
    echo 
    echo "Installation complete."
    echo "This implies your code successfully compiled before installation; you can either scroll up or run \"more $build_log\" to see build results"
  else
    echo
    echo "Installation failed. There was a problem running \"cmake --build . --target install -- -j $nprocs\"" >&2
    echo "Exiting..." >&2
    exit 50
  fi
 
fi



if $run_tests ; then
     COL_YELLOW="\e[33m"
     COL_NULL="\e[0m"
     COL_RED="\e[31m"
     echo 
     echo
     echo
     echo 
     test_log=$LOGDIR/unit_tests_$( date | sed -r 's/[: ]+/_/g' ).log

     cd $BUILDDIR

     for pkgname in $( find . -mindepth 1 -maxdepth 1 -type d -not -name CMakeFiles ); do

       unittestdirs=$( find $BUILDDIR/$pkgname -type d -name "unittest" -not -regex ".*CMakeFiles.*" )

       if [[ -z $unittestdirs ]]; then
             echo
             echo -e "${COL_RED}No unit tests have been written for $pkgname${COL_NULL}"
             echo
             continue
       fi

       num_unit_tests=0

       for unittestdir in $unittestdirs; do
           echo
           echo
           echo "RUNNING UNIT TESTS IN $unittestdir"
           echo "======================================================================"
           for unittest in $unittestdir/* ; do
               if [[ -x $unittest ]]; then
                   echo
                   echo -e "${COL_YELLOW}Start of unit test suite \"$unittest\"${COL_NULL}" |& tee -a $test_log
                   $unittest -l all |& tee -a $test_log
                   echo -e "${COL_YELLOW}End of unit test suite \"$unittest\"${COL_NULL}" |& tee -a $test_log
                   num_unit_tests=$((num_unit_tests + 1))
               fi
           done
 
       done
 
       echo 
       echo -e "${COL_YELLOW}Testing complete for package \"$pkgname\". Ran $num_unit_tests unit test suites.${COL_NULL}"
     done
     
     echo
     echo "Test results are saved in $test_log"
     echo
fi

if $lint; then
    cd $BASEDIR

    if [[ ! -d ./styleguide ]]; then
      echo "Cloning styleguide into $BASEDIR so linting can be applied"
      git clone https://github.com/DUNE-DAQ/styleguide.git
    fi

    for pkgdir in $( find build -mindepth 1 -maxdepth 1 -type d -not -name CMakeFiles ); do
        pkgname=$( echo $pkgdir | sed -r 's!.*/(.*)!\1!' )
        ./styleguide/cpplint/dune-cpp-style-check.sh build sourcecode/$pkgname
    done
fi


