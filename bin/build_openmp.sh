#!/bin/bash
#
#  build_openmp.sh:  Script to build the AOMP runtime libraries and debug libraries.  
#                This script will install in location defined by AOMP env variable
#
# --- Start standard header ----
function getdname(){
   local __DIRN=`dirname "$1"`
   if [ "$__DIRN" = "." ] ; then
      __DIRN=$PWD;
   else
      if [ ${__DIRN:0:1} != "/" ] ; then
         if [ ${__DIRN:0:2} == ".." ] ; then
               __DIRN=`dirname $PWD`/${__DIRN:3}
         else
            if [ ${__DIRN:0:1} = "." ] ; then
               __DIRN=$PWD/${__DIRN:2}
            else
               __DIRN=$PWD/$__DIRN
            fi
         fi
      fi
   fi
   echo $__DIRN
}
thisdir=$(getdname $0)
[ ! -L "$0" ] || thisdir=$(getdname `readlink "$0"`)
. $thisdir/aomp_common_vars
# --- end standard header ----

INSTALL_OPENMP=${INSTALL_OPENMP:-$AOMP_INSTALL_DIR}

if [ "$1" == "-h" ] || [ "$1" == "help" ] || [ "$1" == "-help" ] ; then 
  help_build_aomp
fi

REPO_BRANCH=$AOMP_OPENMP_REPO_BRANCH
REPO_DIR=$AOMP_REPOS/$AOMP_OPENMP_REPO_NAME
checkrepo

PROC=`uname -p`
if [ "$PROC" == "aarch64" ] ; then
   NVPTXGPUS_DEFAULT=""
   NVPTXGPUS=""
else
   CUDAH=`find /usr/local/cuda/targets -type f -name "cuda.h" 2>/dev/null`
   if [ "$CUDAH" == "" ] ; then
      CUDAH=`find /usr/local/cuda/include -type f -name "cuda.h" 2>/dev/null`
   fi
   if [ "$CUDAH" == "" ] ; then
      echo
      echo "ERROR:  THE cuda.h FILE WAS NOT FOUND WITH ARCH $PROC"
      echo "        A CUDA installation is necessary to build libomptarget deviceRTLs"
      echo "        Please install CUDA to build openmp"
      echo
      exit 1
   fi
   # I don't see now nvcc is called, but this eliminates the deprecated warnings
   export CUDAFE_FLAGS="-w"
fi

if [ ! -d $AOMP_REPOS/$AOMP_OPENMP_REPO_NAME ] ; then 
   echo "ERROR:  Missing repository $AOMP_REPOS/$AOMP_OPENMP_REPO_NAME "
   echo "        Consider setting env variables AOMP_REPOS and/or AOMP_OPENMP_REPO_NAME "
   exit 1
fi

# Make sure we can update the install directory
if [ "$1" == "install" ] ; then 
   $SUDO mkdir -p $INSTALL_OPENMP
   $SUDO touch $INSTALL_OPENMP/testfile
   if [ $? != 0 ] ; then 
      echo "ERROR: No update access to $INSTALL_OPENMP"
      exit 1
   fi
   $SUDO rm $INSTALL_OPENMP/testfile
fi

NUM_THREADS=
if [ ! -z `which "getconf"` ]; then
    NUM_THREADS=$(`which "getconf"` _NPROCESSORS_ONLN)
fi

GCCMIN=5
if [ -f /usr/local/cuda/bin/nvcc ] ; then
   CUDAVER=`/usr/local/cuda/bin/nvcc --version | grep compilation | cut -d" " -f5 | cut -d"." -f1 `
   echo "CUDA VERSION IS $CUDAVER"
   if [ $CUDAVER -gt 8 ] ; then
     GCCMIN=7
   fi
fi

function getgcc5orless(){
   _loc=`which gcc`
   [ "$_loc" == "" ] && return
   gccver=`$_loc --version | grep gcc | cut -d")" -f2 | cut -d"." -f1`
   [ $gccver -gt $GCCMIN ] && _loc=`which gcc-$GCCMIN`
   echo $_loc
}
function getgxx5orless(){
   _loc=`which g++`
   [ "$_loc" == "" ] && return
   gxxver=`$_loc --version | grep g++ | cut -d")" -f2 | cut -d"." -f1`
   [ $gxxver -gt $GCCMIN ] && _loc=`which g++-$GCCMIN`
   echo $_loc
}

if [ "$PROC" == "ppc64le" ] ; then
   GCCLOC=`which gcc`
   GXXLOC=`which g++`
else
   GCCLOC=$(getgcc5orless)
   GXXLOC=$(getgxx5orless)
fi
if [ "$GCCLOC" == "" ] ; then
   echo "ERROR: NO ADEQUATE gcc"
   echo "       Please install gcc-5"
   exit 1
fi
if [ "$GXXLOC" == "" ] ; then
   echo "ERROR: NO ADEQUATE g++"
   echo "       Please install g++-5"
   exit 1
fi

COMMON_CMAKE_OPTS="-DOPENMP_ENABLE_LIBOMPTARGET=1
-DCMAKE_INSTALL_PREFIX=$INSTALL_OPENMP
-DOPENMP_TEST_C_COMPILER=$AOMP/bin/clang
-DOPENMP_TEST_CXX_COMPILER=$AOMP/bin/clang++
-DLIBOMPTARGET_NVPTX_ENABLE_BCLIB=ON
-DLIBOMPTARGET_NVPTX_CUDA_COMPILER=$AOMP/bin/clang++
-DLIBOMPTARGET_NVPTX_ALTERNATE_HOST_COMPILER=$GCCLOC
-DLIBOMPTARGET_NVPTX_BC_LINKER=$AOMP/bin/llvm-link
-DLIBOMPTARGET_NVPTX_COMPUTE_CAPABILITIES=$NVPTXGPUS"

export HSA_RUNTIME_PATH=$INSTALL_OPENMP/hsa

if [ "$1" != "nocmake" ] && [ "$1" != "install" ] ; then 

   echo " " 
   echo "This is a FRESH START. ERASING any previous builds in $BUILD_DIR/$AOMP_OPENMP_REPO_NAME "
   echo "Use ""$0 nocmake"" or ""$0 install"" to avoid FRESH START."

   if [ $COPYSOURCE ] ; then 
      mkdir -p $BUILD_DIR/$AOMP_OPENMP_REPO_NAME
      echo rsync -av --exclude ".git" --delete $AOMP_REPOS/$AOMP_OPENMP_REPO_NAME/ $BUILD_DIR/$AOMP_OPENMP_REPO_NAME/ 
      rsync -av --exclude ".git" --delete $AOMP_REPOS/$AOMP_OPENMP_REPO_NAME/ $BUILD_DIR/$AOMP_OPENMP_REPO_NAME/ 
   fi

      echo rm -rf $BUILD_DIR/build/openmp
      rm -rf $BUILD_DIR/build/openmp
      MYCMAKEOPTS="$COMMON_CMAKE_OPTS -DCMAKE_BUILD_TYPE=Release"
      mkdir -p $BUILD_DIR/build/openmp
      cd $BUILD_DIR/build/openmp
      echo " -----Running openmp cmake ---- " 
      echo cmake $MYCMAKEOPTS  $BUILD_DIR/$AOMP_OPENMP_REPO_NAME
      cmake $MYCMAKEOPTS  $BUILD_DIR/$AOMP_OPENMP_REPO_NAME
      if [ $? != 0 ] ; then 
         echo "ERROR openmp cmake failed. Cmake flags"
         echo "      $MYCMAKEOPTS"
         exit 1
      fi

      echo rm -rf $BUILD_DIR/build/openmp_debug
      rm -rf $BUILD_DIR/build/openmp_debug
      export OMPTARGET_DEBUG=1
      MYCMAKEOPTS="$COMMON_CMAKE_OPTS -DLIBOMPTARGET_NVPTX_DEBUG=ON -DCMAKE_BUILD_TYPE=Debug -DOMPTARGET_DEBUG=1"
      mkdir -p $BUILD_DIR/build/openmp_debug
      cd $BUILD_DIR/build/openmp_debug
      echo
      echo " -----Running openmp cmake for debug ---- " 
      echo cmake $MYCMAKEOPTS  $BUILD_DIR/$AOMP_OPENMP_REPO_NAME
      cmake $MYCMAKEOPTS  $BUILD_DIR/$AOMP_OPENMP_REPO_NAME
      if [ $? != 0 ] ; then 
         echo "ERROR openmp debug cmake failed. Cmake flags"
         echo "      $MYCMAKEOPTS"
         exit 1
      fi
fi

cd $BUILD_DIR/build/openmp
echo
echo " -----Running make for $BUILD_DIR/build/openmp ---- "
make -j $NUM_THREADS
if [ $? != 0 ] ; then 
      echo " "
      echo "ERROR: make -j $NUM_THREADS  FAILED"
      echo "To restart:" 
      echo "  cd $BUILD_DIR/build/openmp"
      echo "  make"
      exit 1
fi

cd $BUILD_DIR/build/openmp_debug
echo
echo
echo " -----Running make for $BUILD_DIR/build/openmp_debug ---- "
export OMPTARGET_DEBUG=1
make -j $NUM_THREADS
if [ $? != 0 ] ; then 
      echo "ERROR make -j $NUM_THREADS failed"
      exit 1
else
   if [ "$1" != "install" ] ; then 
      echo
      echo "Successful build of ./build_openmp.sh .  Please run:"
      echo "  ./build_openmp.sh install "
      echo "to install into directory $INSTALL_OPENMP/lib and $INSTALL_OPENMP/lib-debug"
      echo
  fi
fi

#  ----------- Install only if asked  ----------------------------
if [ "$1" == "install" ] ; then 
      cd $BUILD_DIR/build/openmp
      echo
      echo " -----Installing to $INSTALL_OPENMP/lib ----- " 
      $SUDO make install 
      if [ $? != 0 ] ; then 
         echo "ERROR make install failed "
         exit 1
      fi
      cd $BUILD_DIR/build/openmp_debug
      echo
      echo " -----Installing to $INSTALL_OPENMP/lib-debug ---- " 
      $SUDO make install 
      if [ $? != 0 ] ; then 
         echo "ERROR make install failed "
         exit 1
      fi
fi