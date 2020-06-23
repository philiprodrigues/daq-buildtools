#!/bin/env bash

empty_dir_check=true
edits_check=true

setup_script=setup_build_environment
build_script=build_daq_software.sh

products_dirs="/cvmfs/dune.opensciencegrid.org/dunedaq/DUNE/products" 

starttime_d=$( date )
starttime_s=$( date +%s )

for pd in $( echo $products_dirs | tr ":" " " ) ; do
    if [[ ! -e $pd ]]; then
	echo "Unable to find needed products area \"$pd\"; exiting..." >&2
	exit 1
    fi
done

gcc_version=v8_2_0
gcc_version_qualifier=e19  # Make sure this matches with the version

boost_version=v1_70_0
cetlib_version=v3_10_00
cmake_version=v3_17_2
nlohmann_json_version=v3_2_0
TRACE_version=v3_15_09
folly_version=v2020_05_25
ninja_version=v1_8_2

boost_version_with_dots=$( echo $boost_version | sed -r 's/^v//;s/_/./g' )
nlohmann_json_with_dots=$( echo $nlohmann_json_version | sed -r 's/^v//;s/_/./g' )
TRACE_version_with_dots=$( echo $TRACE_version | sed -r 's/^v//;s/_/./g' )

basedir=$PWD
builddir=$basedir/build
logdir=$basedir/log

packages="daq-buildtools:develop appfwk:develop ers:dune/ers-00-26-00"

export USER=${USER:-$(whoami)}
export HOSTNAME=${HOSTNAME:-$(hostname)}

if [[ -z $USER || -z $HOSTNAME ]]; then
    echo "Problem getting one or both of the environment variables \$USER and \$HOSTNAME; exiting..." >&2
    exit 10
fi

if $empty_dir_check && [[ -n $( ls -a1 | grep -E -v "^quick-start.*" | grep -E -v "^\.\.?$" ) ]]; then

    cat<<EOF >&2                                                                               

There appear to be files in $basedir besides this script; this script
should only be run in a clean directory. Exiting...

EOF
    exit 20

elif ! $empty_dir_check ; then

    cat<<EOF >&2

WARNING: The check for whether any files besides this script exist in
its directory has been switched off. This may mean assumptions the
script makes are violated, resulting in undesired behavior.

EOF

    sleep 5

fi

if $edits_check ; then

    qs_tmpdir=/tmp/${USER}_for_quick-start
    mkdir -p $qs_tmpdir

    cd $qs_tmpdir
    rm -f quick-start.sh
    repoloc=https://raw.githubusercontent.com/DUNE-DAQ/daq-buildtools/develop/bin/quick-start.sh
    curl -O $repoloc

    potential_edits=$( diff $basedir/quick-start.sh $qs_tmpdir/quick-start.sh )

    if [[ -n $potential_edits ]]; then

	cat<<EOF >&2                                                                                                             
Error: this script you're trying to run doesn't match with the version
of the script at the head of the develop branch in the daq-buildtool's
central repository. This may mean that this script makes obsolete
assumptions, etc., which could compromise your working
environment. Please delete this script and install your daq-buildtools
area according to the instructions at https://github.com/DUNE-DAQ/app-framework/wiki/Compiling-and-running

EOF

	exit 40

    fi

    cd $basedir

else 

cat<<EOF >&2

WARNING: The feature whereby this script checks itself to see if it's
different than its version at the head of the central repo's develop
branch has been switched off. User assumes the risk that the script
may make out-of-date assumptions.

EOF

sleep 5

fi # if $edits_check

cat<<EOF > $setup_script

if [[ -z \$DUNE_SETUP_BUILD_ENVIRONMENT_SCRIPT_SOURCED ]]; then

echo "This script hasn't yet been sourced (successfully) in this shell; setting up the build environment"

EOF

for pd in $( echo $products_dirs | tr ":" " " ); do

    cat<<EOF >> $setup_script

. $pd/setup
if [[ "\$?" != 0 ]]; then
  echo "Executing \". $pd/setup\" resulted in a nonzero return value; returning..."
  return 10
fi

EOF

done


cat<<EOF >> $setup_script

setup_returns=""
setup cmake $cmake_version 
setup_returns=\$setup_returns"\$? "
setup gcc $gcc_version
setup_returns=\$setup_returns"\$? "
setup boost $boost_version -q ${gcc_version_qualifier}:prof
setup_returns=\$setup_returns"\$? "
setup cetlib $cetlib_version -q ${gcc_version_qualifier}:prof
setup_returns=\$setup_returns"\$? "
setup TRACE $TRACE_version
setup_returns=\$setup_returns"\$? "
setup folly $folly_version -q ${gcc_version_qualifier}:prof
setup_returns=\$setup_returns"\$? "
setup ninja $ninja_version 2>/dev/null # Don't care if it fails

if [[ "\$setup_returns" =~ [1-9] ]]; then
  echo "At least one of the packages this script attempted to set up didn't set up correctly; returning..." >&2
  cd \$origdir
  return 1
fi

export DUNE_SETUP_BUILD_ENVIRONMENT_SCRIPT_SOURCED=1
echo "This script has been sourced successfully"
echo

else

echo "This script appears to have already been sourced successfully; returning..." >&2
return 10

fi    # if DUNE_SETUP_BUILD_ENVIRONMENT_SCRIPT_SOURCED wasn't defined


EOF

cat<<EOF > $build_script
#!/bin/bash

run_tests=false
clean_build=false 

for arg in "\$@" ; do
  if [[ "\$arg" == "--help" ]]; then
    echo "Usage: "\$( basename \$0 )" --clean --unittest --help "
    echo
    echo " --clean means the contents of ./build are deleted and CMake's config+generate+build stages are run"
    echo " --unittest means that unit test executables found in build are all run"
    echo
    echo "All arguments are optional. With no arguments, CMake will typically just run "
    echo "build, unless build/CMakeCache.txt is missing"
    echo
    exit 0    

  elif [[ "\$arg" == "--clean" ]]; then
    clean_build=true
  elif [[ "\$arg" == "--unittest" ]]; then
    run_tests=true
  else
    echo "Unknown argument provided; run with \" --help\" to see valid options. Exiting..." >&2
    exit 1
  fi
done



builddir=$builddir

if [[ ! -d \$builddir ]]; then
    echo "Expected build directory \$builddir not found; exiting..." >&2
    exit 1
fi

if [[ -z \$DUNE_SETUP_BUILD_ENVIRONMENT_SCRIPT_SOURCED ]]; then
echo
echo "It appears you haven't yet sourced \"./setup_build_environment\" yet; please source it before running this script. Exiting..."
echo
exit 2
fi

cd \$builddir

if \$clean_build; then 
  
   # Want to be damn sure of we're in the right directory, rm -rf * is no joke...

   if  [[ \$( echo \$PWD | sed -r 's!.*/(.*)!\1!' ) =~ ^build/*$ ]]; then
     echo "Clean build requested, will delete all the contents of build directory \"\$PWD\"."
     echo "If you wish to abort, you have 5 seconds to hit Ctrl-c"
     sleep 5
     rm -rf *
   else
     echo "SCRIPT ERROR: you requested a clean build, but this script thinks that \$builddir isn't the build directory." >&2
     echo "Please contact John Freeman at jcfree@fnal.gov and notify him of this message" >&2
     exit 10
   fi

fi


build_log=$logdir/build_attempt_\$( date | sed -r 's/[: ]+/_/g' ).log

# We only need to explicitly run CMake if the cache has not yet been generated

if ! [ -e CMakeCache.txt ];then

generator_arg=
if [ "x\${SETUP_NINJA}" != "x" ]; then
  generator_arg="-G Ninja"
fi

starttime_cfggen_d=\$( date )
starttime_cfggen_s=\$( date +%s )
unbuffer cmake \${generator_arg} .. |& tee \$build_log
retval=\${PIPESTATUS[0]}  # Captures the return value of cmake .., not tee
endtime_cfggen_d=\$( date )
endtime_cfggen_s=\$( date +%s )

if [[ "\$retval" == "0" ]]; then

sed -i -r '1 i\# If you want to add or edit a variable, be aware that the config+generate stage is skipped in $build_script if this file exists' \$builddir/CMakeCache.txt
sed -i -r '2 i\# Consider setting variables you want cached with the CACHE option in the relevant CMakeLists.txt file instead' \$builddir/CMakeCache.txt

cfggentime=\$(( endtime_cfggen_s - starttime_cfggen_s ))
echo "CMake's config+generate stages took \$cfggentime seconds"
echo "Start time: \$starttime_cfggen_d"
echo "End time:   \$endtime_cfggen_d"

else

echo
echo "There was a problem running \"cmake ..\" from \$builddir (i.e.," >&2
echo "CMake's config+generate stages). Scroll up for" >&2
echo "details or look at \${build_log}. Exiting..."
echo

    exit 30
fi

else

echo "The config+generate stage was skipped as CMakeCache.txt was already found in \$builddir"

fi # !-e CMakeCache.txt

nprocs=\$( grep -E "^processor\s*:\s*[0-9]+" /proc/cpuinfo  | wc -l )
nprocs_argument=""
 
if [[ -n \$nprocs && \$nprocs =~ ^[0-9]+$ ]]; then
    echo "This script believes you have \$nprocs processors available on this system, and will use as many of them as it can"
    nprocs_argument=" -j \$nprocs"
else
    echo "Unable to determine the number of processors available, will not pass the \"-j <nprocs>\" argument on to the build stage" >&2
fi




starttime_build_d=\$( date )
starttime_build_s=\$( date +%s )
if [ "x\${SETUP_NINJA}" == "x" ]; then
unbuffer cmake --build . -- \$nprocs_argument |& tee -a \$build_log
else
unbuffer ninja \$nprocs_argument |& tee -a \$build_log
fi
retval=\${PIPESTATUS[0]}  # Captures the return value of cmake --build, not tee
endtime_build_d=\$( date )
endtime_build_s=\$( date +%s )

if [[ "\$retval" == "0" ]]; then

buildtime=\$((endtime_build_s - starttime_build_s))

else

echo
echo "There was a problem running \"cmake --build .\" from \$builddir (i.e.," >&2
echo "CMake's build stage). Scroll up for" >&2
echo "details or look at the build log via \"more \${build_log}\". Exiting..."
echo

   exit 40
fi

if [[ -e \$builddir/appfwk/scripts/setupForRunning.sh ]]; then
  . \$builddir/appfwk/scripts/setupForRunning.sh
else
  echo
  echo "Error: this script makes an incorrect assumption about the existence of \$builddir/appfwk/scripts/setupForRunning.sh; exiting..." >&2
  echo
  exit 50
fi

num_estimated_warnings=\$( grep "warning: " \${build_log} | wc -l )

echo

if [[ -n \$cfggentime ]]; then
  echo
  echo "config+generate stage took \$cfggentime seconds"
  echo "Start time: \$starttime_cfggen_d"
  echo "End time:   \$endtime_cfggen_d"
  echo
else
  echo "config+generate stage was skipped"
fi
echo "build stage took \$buildtime seconds"
echo "Start time: \$starttime_build_d"
echo "End time:   \$endtime_build_d"
echo
echo "Output of build contains an estimated \$num_estimated_warnings warnings, and can be viewed later via: "
echo "\"more \${build_log}\""
echo

if [[ -n \$cfggentime ]]; then
  echo "CMake's config+generate+build stages all completed successfully"
  echo
else
  echo "CMake's build stage completed successfully"
fi

if \$run_tests ; then
 
     echo 
     echo
     echo
     echo 
     test_log=$logdir/unit_tests_\$( date | sed -r 's/[: ]+/_/g' ).log

     for unittestdir in \$( find \$builddir -type d -name "unittest" -not -regex ".*CMakeFiles.*" ); do
       echo
       echo
       echo "RUNNING UNIT TESTS IN \$unittestdir"
       echo "======================================================================"
       for unittest in \$unittestdir/* ; do
           if [[ -x \$unittest ]]; then
               unbuffer \$unittest -l all |& tee \$test_log
           fi
       done
 
     done
 
     echo 
     echo 
     echo "Testing complete."
     echo "This implies your code compiled before testing, though you can either scroll up or run \"more \$build_log\" to see build results"
     echo "Test results are saved and can be viewed via \"more \$test_log\""
     echo
fi





EOF
chmod +x $build_script

cat >CMakeLists.txt<<EOF

cmake_minimum_required(VERSION 3.12)

project(dune-app-framework LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(BUILD_SHARED_LIBS ON)

# Directories should always be added *before* the current path
set(CMAKE_INCLUDE_DIRECTORIES_PROJECT_BEFORE ON)

find_package(Boost $boost_version_with_dots COMPONENTS unit_test_framework program_options REQUIRED)
find_package(TRACE $TRACE_version_with_dots REQUIRED)

find_package(nlohmann_json $nlohmann_json_version_with_dots )

if(NOT \${nlohmann_json_FOUND})
  message("nlohmann_json NOT FOUND! Downloading single-header from GitHub!")
  file(DOWNLOAD https://github.com/nlohmann/json/raw/develop/single_include/nlohmann/json.hpp nlohmann/json.hpp)
  include_directories(\${CMAKE_BINARY_DIR})
endif()

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

add_compile_options( -g -pedantic -Wall -Wextra )

set(DAQ_LIBRARIES_UNIVERSAL ers pthread)
set(DAQ_INCLUDES_UNIVERSAL \${Boost_INCLUDE_DIRS})

set(DAQ_LIBRARIES_UNIVERSAL_EXE \${Boost_PROGRAM_OPTIONS_LIBRARY} \${DAQ_LIBRARIES_UNIVERSAL})

message(WARNING "ctest will *not* work! enable_testing() call had to be disabled since the ers package defines a target with the name \"test\", which causes enable_testing() to fail")
#enable_testing()

set(CMAKE_MODULE_PATH \${CMAKE_CURRENT_SOURCE_DIR}/daq-buildtools/CMake \${CMAKE_MODULE_PATH})
include(DAQ)

include_directories(SYSTEM \${DAQ_INCLUDES_UNIVERSAL})

include_directories(SYSTEM \${CMAKE_SOURCE_DIR}/ers)
add_subdirectory(ers)

include_directories(\${CMAKE_SOURCE_DIR}/appfwk/include)
add_subdirectory(appfwk)



EOF


for package in $packages; do
    packagename=$( echo $package | sed -r 's/:.*//g' )
    packagebranch=$( echo $package | sed -r 's/.*://g' )
    echo "Cloning $packagename repo, will use $packagebranch branch..."
    git clone https://github.com/DUNE-DAQ/${packagename}.git
    cd ${packagename}
    git checkout $packagebranch

    if [[ "$?" != "0" ]]; then
	echo >&2
	echo "WARNING: unable to check out $packagebranch branch of ${packagename}. Among other consequences, your build may fail..." >&2
	echo >&2
	sleep 5
    fi
    cd ..
done

mkdir -p $builddir
mkdir -p $logdir

endtime_d=$( date )
endtime_s=$( date +%s )

echo
echo "Total time to run "$( basename $0)": "$(( endtime_s - starttime_s ))" seconds"
echo "Start time: $starttime_d"
echo "End time:   $endtime_d"
echo
echo "To build, execute the following commands: "
echo ". ./$setup_script"
echo "./$build_script  # And add \" --help\" to just see your options"
echo
echo "Script completed successfully"
echo
exit 0

