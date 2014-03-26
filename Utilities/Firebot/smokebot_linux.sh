#!/bin/bash

# Smokebot
# This script is a simplified version of Kris Overholt's firebot script.
# It runs the smokeview verification suite (not FDS) on the latest
# revision of the repository.  It does not erase files that are not
# the repository.  This allows one to test working files before they
# have been committed.  

#  ===================
#  = Input variables =
#  ===================

FIREBOT_QUEUE=smokebot
MAKEMOVIES=
RUNAUTO=
BUILDBUNDLE=
RUNDEBUG="1"
OPENMP=
RUN_OPENMP=

notfound=`icc -help 2>&1 | tail -1 | grep "not found" | wc -l`
if [ "$notfound" == "1" ] ; then
  export haveCC="0"
  USEINSTALL="-i"
  USEINSTALL2="-u"
else
  export haveCC="1"
  USEINSTALL=
  USEINSTALL2=
fi

while getopts 'abmo:q:s' OPTION
do
case $OPTION in
  a)
   RUNAUTO="y"
   ;;
  b)
   BUILDBUNDLE="y"
   ;;
  m)
   MAKEMOVIES="1"
   ;;
  o)
   nthreads="$OPTARG"
   OPENMP=openmp_
   RUN_OPENMP="-o $nthreads"
   ;;
  q)
   FIREBOT_QUEUE="$OPTARG"
   ;;
  s)
   RUNDEBUG="0"
   ;;
esac
done
shift $(($OPTIND-1))

DB=_db
IB=
if [ "$FDSNETWORK" == "infiniband" ] ; then
IB=ib
fi

platform="linux"
if [ "`uname`" == "Darwin" ]
then
  platform="osx"
fi
export platform

FIREBOT_USERNAME="`whoami`"

cd
FIREBOT_HOME_DIR="`pwd`"
FIREBOT_DIR="$FIREBOT_HOME_DIR/SMOKEBOT"
export FDS_SVNROOT="$FIREBOT_HOME_DIR/FDS-SMV"
export SMV_Summary="$FDS_SVNROOT/Manuals/SMV_Summary"
CFAST_SVNROOT="$FIREBOT_HOME_DIR/cfast"
ERROR_LOG=$FIREBOT_DIR/output/errors
TIME_LOG=$FIREBOT_DIR/output/timings
WARNING_LOG=$FIREBOT_DIR/output/warnings
GUIDE_DIR=$FIREBOT_DIR/guides

THIS_FDS_AUTHOR=
THIS_FDS_FAILED=0
FDS_STATUS_FILE=$FDS_SVNROOT/FDS_status
LAST_FDS_FAILED=0
if [ -e $FDS_STATUS_FILE ] ; then
  LAST_FDS_FAILED=`cat $FDS_STATUS_FILE`
fi

# Load mailing list for status report
source $FIREBOT_DIR/firebot_email_list.sh

mailTo=$mailToSMV
if [[ "$LAST_FDS_FAILED" == "1" ]] ; then
  mailTo=$mailToFDS
fi

export JOBPREFIX=SB_

#  =============================================
#  = Smokebot timing and notification mechanism =
#  =============================================

# This routine checks the elapsed time of Smokebot.
# If Smokebot runs more than 12 hours, an email notification is sent.
# This is a notification only and does not terminate Smokebot.
# This check runs during Stages 3 and 5.

# Start firebot timer
START_TIME=$(date +%s)

# Set time limit (43,200 seconds = 12 hours)
TIME_LIMIT=43200
TIME_LIMIT_EMAIL_NOTIFICATION="unsent"

run_auto()
{
  SMV_SOURCE=$FDS_SVNROOT/SMV/source
  SVN_SMVFILE=$FDS_SVNROOT/smv_revision
  SVN_SMVLOG=$FDS_SVNROOT/smv_log

  FDS_SOURCE=$FDS_SVNROOT/FDS_Source
  SVN_FDSFILE=$FDS_SVNROOT/fds_revision
  SVN_FDSLOG=$FDS_SVNROOT/FDS_log

  SMOKEBOTDIR=~/SMOKEBOT/
  SMOKEBOTEXE=./run_smokebot.sh

  MESSAGE_FILE=$FDS_SVNROOT/message

  cd $SMV_SOURCE
  svn update > /dev/null
  THIS_SMVSVN=`svn info | tail -3 | head -1 | awk '{print $4}'`
  THIS_SMVAUTHOR=`svn info | tail -4 | head -1 | awk '{print $4}'`
  LAST_SMVSVN=`cat $SVN_SMVFILE`
  svn log -r $THIS_SMVSVN > $SVN_SMVLOG

  cd $FDS_SOURCE
  svn update > /dev/null
  THIS_FDSSVN=`svn info | tail -3 | head -1 | awk '{print $4}'`
  THIS_FDSAUTHOR=`svn info | tail -4 | head -1 | awk '{print $4}'`
  LAST_FDSSVN=`cat $SVN_FDSFILE`
  svn log -r $THIS_FDSSVN > $SVN_FDSLOG

  if [[ $THIS_SMVSVN == $LAST_SMVSVN && $THIS_FDSSVN == $LAST_FDSSVN ]] ; then
    exit
  fi

  rm -f $MESSAGE_FILE
  if [[ $THIS_SMVSVN != $LAST_SMVSVN ]] ; then
    echo $THIS_SMVSVN>$SVN_SMVFILE
    echo -e "smokeview source has changed. $LAST_SMVSVN->$THIS_SMVSVN($THIS_SMVAUTHOR)" >> $MESSAGE_FILE
    cat $SVN_SMVLOG >> $MESSAGE_FILE
  fi
  if [[ $THIS_FDSSVN != $LAST_FDSSVN ]] ; then
    echo $THIS_FDSSVN>$SVN_FDSFILE
    echo -e "FDS source has changed. $LAST_FDSSVN->$THIS_FDSSVN($THIS_FDSAUTHOR)" >> $MESSAGE_FILE
    cat $SVN_FDSLOG >> $MESSAGE_FILE
  fi
  echo -e "Smokebot run initiated." >> $MESSAGE_FILE
  cat $MESSAGE_FILE | mail -s "smokebot run initiated" $mailTo > /dev/null
}

MKDIR ()
{
  DIR=$1
  if [ ! -d $DIR ]
  then
    echo Creating directory $DIR
    mkdir $DIR
  fi
}

check_time_limit()
{
   if [ "$TIME_LIMIT_EMAIL_NOTIFICATION" == "sent" ]
   then
      # Continue along
      :
   else
      CURRENT_TIME=$(date +%s)
      ELAPSED_TIME=$(echo "$CURRENT_TIME-$START_TIME"|bc)

      if [ $ELAPSED_TIME -gt $TIME_LIMIT ]
      then
         echo -e "smokebot has been running for more than 12 hours in Stage ${TIME_LIMIT_STAGE}. \n\nPlease ensure that there are no problems. \n\nThis is a notification only and does not terminate smokebot." | mail -s "smokebot Notice: smokebot has been running for more than 12 hours." $mailTo > /dev/null
         TIME_LIMIT_EMAIL_NOTIFICATION="sent"
      fi
   fi
}

#  ========================
#  = Additional functions =
#  ========================

set_files_world_readable()
{
   cd $FDS_SVNROOT
   chmod -R go+r *
}

clean_smokebot_history()
{
   
   # Clean Smokebot metafiles
   MKDIR $FIREBOT_DIR
   cd $FIREBOT_DIR
   MKDIR guides
   MKDIR history
   MKDIR output
   rm -f output/* > /dev/null
}

#  ========================
#  ========================
#  = Smokebot Build Stages =
#  ========================
#  ========================

#  ===================================
#  = Stage 0 - External dependencies =
#  ===================================

update_and_compile_cfast()
{
   cd $FIREBOT_HOME_DIR

   # Check to see if CFAST repository exists
   if [ -e "$CFAST_SVNROOT" ]
   # If yes, then update the CFAST repository and compile CFAST
   then
      echo "Updating and compiling CFAST:" > $FIREBOT_DIR/output/stage0_cfast
      cd $CFAST_SVNROOT/CFAST
      
      # Update to latest SVN revision
      svn update >> $FIREBOT_DIR/output/stage0_cfast 2>&1
      
   # If no, then checkout the CFAST repository and compile CFAST
   else
      echo "Downloading and compiling CFAST:" > $FIREBOT_DIR/output/stage0_cfast
      mkdir -p $CFAST_SVNROOT
      cd $CFAST_SVNROOT

      svn co https://cfast.googlecode.com/svn/trunk/cfast/trunk/CFAST CFAST >> $FIREBOT_DIR/output/stage0_cfast 2>&1
      
   fi
    # Build CFAST
    cd $CFAST_SVNROOT/CFAST/intel_${platform}_64
    rm -f cfast6_${platform}_64
    make --makefile ../makefile clean &> /dev/null
    ./make_cfast.sh >> $FIREBOT_DIR/output/stage0_cfast 2>&1

   # Check for errors in CFAST compilation
   cd $CFAST_SVNROOT/CFAST/intel_${platform}_64
   if [ -e "cfast6_${platform}_64" ]
   then
      stage0_success=true
   else
      echo "Errors from Stage 0 - CFAST:" >> $ERROR_LOG
      echo "CFAST failed to compile" >> $ERROR_LOG
      cat $FIREBOT_DIR/output/stage0_cfast >> $ERROR_LOG
      echo "" >> $ERROR_LOG
   fi

}

#  ============================
#  = Stage 1 - SVN operations =
#  ============================

clean_svn_repo()
{
   # Check to see if FDS repository exists
   if [ -e "$FDS_SVNROOT" ]
   then
   # If not, create FDS repository and checkout
     dummy=true
   else
      echo "Downloading FDS repository:" >> $FIREBOT_DIR/output/stage1 2>&1
      cd $FIREBOT_HOME_DIR
      svn co https://fds-smv.googlecode.com/svn/trunk/FDS/trunk/ FDS-SMV >> $FIREBOT_DIR/output/stage1 2>&1
   fi
}

do_svn_checkout()
{
   cd $FDS_SVNROOT
   echo "Checking out latest revision." >> $FIREBOT_DIR/output/stage1 2>&1
   svn update >> $FIREBOT_DIR/output/stage1 2>&1
   SVN_REVISION=`tail -n 1 $FIREBOT_DIR/output/stage1 | sed "s/[^0-9]//g"`
}

check_svn_checkout()
{
   cd $FDS_SVNROOT
   # Check for SVN errors
   if [[ `grep -E 'Updated|At revision' $FIREBOT_DIR/output/stage1 | wc -l` -ne 1 ]];
   then
      echo "Errors from Stage 1 - SVN operations:" >> $ERROR_LOG
      cat $FIREBOT_DIR/output/stage1 >> $ERROR_LOG
      echo "" >> $ERROR_LOG
      email_build_status
      exit
   else
      stage1_success=true
   fi
}

#  ==================================
#  = Stage 2a/b - Compile FDS debug =
#  ==================================

compile_fds_db()
{
   # Clean and compile FDS debug
   cd $FDS_SVNROOT/FDS_Compilation/${OPENMP}intel_${platform}_64_db
   rm -f fds_${OPENMP}intel_${platform}_64_db
   make --makefile ../makefile clean &> /dev/null
   ./make_fds.sh &> $FIREBOT_DIR/output/stage2a
}

compile_fds_mpi_db()
{
   # Clean and compile mpi FDS debug
   cd $FDS_SVNROOT/FDS_Compilation/mpi_intel_${platform}_64$IB$DB
   rm -f fds_mpi_intel_${platform}_64$IB$DB
   make --makefile ../makefile clean &> /dev/null
   ./make_fds.sh &> $FIREBOT_DIR/output/stage2b
}

check_compile_fds_db()
{
   # Check for errors in FDS debug compilation
   cd $FDS_SVNROOT/FDS_Compilation/${OPENMP}intel_${platform}_64_db
   if [ -e "fds_${OPENMP}intel_${platform}_64_db" ]
   then
      stage2a_success=true
   else
      echo "Errors from Stage 2a - Compile FDS debug:" >> $ERROR_LOG
      cat $FIREBOT_DIR/output/stage2a >> $ERROR_LOG
      echo "" >> $ERROR_LOG
      THIS_FDS_FAILED=1
   fi

   # Check for compiler warnings/remarks
   if [[ `grep -A 5 -E 'warning|remark' ${FIREBOT_DIR}/output/stage2a` == "" ]]
   then
      # Continue along
      :
   else
      echo "Stage 2a warnings:" >> $WARNING_LOG
      grep -A 5 -E 'warning|remark' ${FIREBOT_DIR}/output/stage2a >> $WARNING_LOG
      echo "" >> $WARNING_LOG
   # if the executable does not exist then an email has already been sent
      if [ -e "fds_${OPENMP}intel_${platform}_64_db" ] ; then
        THIS_FDS_FAILED=1
      fi
   fi
}

check_compile_fds_mpi_db()
{
   # Check for errors in FDS debug compilation
   cd $FDS_SVNROOT/FDS_Compilation/mpi_intel_${platform}_64$IB$DB
   if [ -e "fds_mpi_intel_${platform}_64$IB$DB" ]
   then
      stage2b_success=true
   else
      echo "Errors from Stage 2b - Compile FDS MPI debug:" >> $ERROR_LOG
      cat $FIREBOT_DIR/output/stage2b >> $ERROR_LOG
      echo "" >> $ERROR_LOG
      THIS_FDS_FAILED=1
   fi

   # Check for compiler warnings/remarks
   if [[ `grep -A 5 -E 'warning|remark' ${FIREBOT_DIR}/output/stage2b| grep -v 'feupdateenv is not implemented'` == "" ]]
   then
      # Continue along
      :
   else
      echo "Stage 2b warnings:" >> $WARNING_LOG
      grep -A 5 -E 'warning|remark' ${FIREBOT_DIR}/output/stage2b | grep -v 'feupdateenv is not implemented'>> $WARNING_LOG
      echo "" >> $WARNING_LOG
   # if the executable does not exist then an email has already been sent
      if [ -e "fds_mpi_intel_${platform}_64$IB$DB" ] ; then
        THIS_FDS_FAILED=1
      fi
   fi
}

#  =================================================
#  = Stage 3 - Run verification cases (debug mode) =
#  =================================================

wait_verification_cases_debug_start()
{
   # Scans qstat and waits for verification cases to start
   if [[ "$FIREBOT_QUEUE" == "none" ]]
   then
     while [[ `ps -u $USER -f | fgrep .fds | grep -v grep` != '' ]]; do
        JOBS_REMAINING=`ps -u $USER -f | fgrep .fds | grep -v grep | wc -l`
        echo "Waiting for ${JOBS_REMAINING} verification cases to start." >> $FIREBOT_DIR/output/stage3
        TIME_LIMIT_STAGE="3"
        check_time_limit
        sleep 30
     done
   else
     while [[ `qstat -a | grep $(whoami) | grep Q` != '' ]]; do
        JOBS_REMAINING=`qstat -a | grep $(whoami) | grep $JOBPREFIX | grep Q | wc -l`
        echo "Waiting for ${JOBS_REMAINING} verification cases to start." >> $FIREBOT_DIR/output/stage3
        TIME_LIMIT_STAGE="3"
        check_time_limit
        sleep 30
     done
   fi
}

wait_verification_cases_debug_end()
{
   # Scans qstat and waits for verification cases to end
   if [[ "$FIREBOT_QUEUE" == "none" ]]
   then
     while [[ `ps -u $USER -f | fgrep .fds | grep -v grep` != '' ]]; do
        JOBS_REMAINING=`ps -u $USER -f | fgrep .fds | grep -v grep | wc -l`
        echo "Waiting for ${JOBS_REMAINING} verification cases to complete." >> $FIREBOT_DIR/output/stage3
        TIME_LIMIT_STAGE="3"
        check_time_limit
        sleep 30
     done
   else
     while [[ `qstat -a | grep $(whoami) | grep $JOBPREFIX` != '' ]]; do
        JOBS_REMAINING=`qstat -a | grep $(whoami) | grep $JOBPREFIX | wc -l`
        echo "Waiting for ${JOBS_REMAINING} verification cases to complete." >> $FIREBOT_DIR/output/stage3
        TIME_LIMIT_STAGE="3"
        check_time_limit
        sleep 30
     done
   fi
}

run_verification_cases_debug()
{

   #  =====================
   #  = Run all SMV cases =
   #  =====================

   cd $FDS_SVNROOT/Verification/scripts

   # Submit SMV verification cases and wait for them to start
   echo 'Running SMV verification cases:' >> $FIREBOT_DIR/output/stage3 2>&1
   ./Run_SMV_Cases.sh $USEINSTALL2 -d -q $FIREBOT_QUEUE >> $FIREBOT_DIR/output/stage3 2>&1
   wait_verification_cases_debug_start

   # Wait some additional time for all cases to start
   sleep 30

   # Stop all cases
   ./Run_SMV_Cases.sh $USEINSTALL2 -d -s >> $FIREBOT_DIR/output/stage3 2>&1
   echo "" >> $FIREBOT_DIR/output/stage3 2>&1

   # Wait for SMV verification cases to end
   wait_verification_cases_debug_end

   #  ======================
   #  = Remove .stop files =
   #  ======================

   # Remove all .stop and .err files from Verification directories (recursively)
   cd $FDS_SVNROOT/Verification
   find . -name '*.stop' -exec rm -f {} \;
   find . -name '*.err' -exec rm -f {} \;
   find Visualization -name '*.smv' -exec rm -f {} \;
   find scripts/Outfiles -name '*.out' -exec rm -f {} \;
   find WUI -name '*.smv' -exec rm -f {} \;
}

check_verification_cases_debug()
{
   # Scan and report any errors in FDS verification cases
   cd $FDS_SVNROOT/Verification/Visualization

   if [[ `grep 'Run aborted' -rI ${FIREBOT_DIR}/output/stage3` == "" ]] && \
      [[ `grep Segmentation -rI * ../WUI/*` == "" ]] && \
      [[ `grep ERROR: -rI * ../WUI/*` == "" ]] && \
      [[ `grep 'STOP: Numerical' -rI * ../WUI/*` == "" ]] && \
      [[ `grep -A 20 forrtl -rI * ../WUI/*` == "" ]]
   then
      stage3_success=true
   else
      grep 'Run aborted' -rI $FIREBOT_DIR/output/stage3 > $FIREBOT_DIR/output/stage3_errors
      grep Segmentation -rI * ../WUI/* >> $FIREBOT_DIR/output/stage3_errors
      grep ERROR: -rI * ../WUI/* >> $FIREBOT_DIR/output/stage3_errors
      grep 'STOP: Numerical' -rI * ../WUI/* >> $FIREBOT_DIR/output/stage3_errors
      grep -A 20 forrtl -rI * ../WUI/* >> $FIREBOT_DIR/output/stage3_errors
      
      echo "Errors from Stage 3 - Run verification cases (debug mode):" >> $ERROR_LOG
      cat $FIREBOT_DIR/output/stage3_errors >> $ERROR_LOG
      echo "" >> $ERROR_LOG
      THIS_FDS_FAILED=1
   fi
   if [[ `grep 'Warning' -rI ${FIREBOT_DIR}/output/stage3` == "" ]] 
   then
      no_warnings=true
   else
      echo "Stage 3 warnings:" >> $WARNING_LOG
      grep 'Warning' -rI ${FIREBOT_DIR}/output/stage3 >> $WARNING_LOG
      echo "" >> $WARNING_LOG
   fi
}

#  ====================================
#  = Stage 4a/b - Compile FDS release =
#  ====================================

compile_fds()
{
   # Clean and compile FDS
   cd $FDS_SVNROOT/FDS_Compilation/${OPENMP}intel_${platform}_64
   rm -f fds_${OPENMP}intel_${platform}_64
   make --makefile ../makefile clean &> /dev/null
   ./make_fds.sh &> $FIREBOT_DIR/output/stage4a
}

compile_fds_mpi()
{
   # Clean and compile FDS
   cd $FDS_SVNROOT/FDS_Compilation/mpi_intel_${platform}_64$IB
   rm -f fds_mpi_intel_${platform}_64$IB
   make --makefile ../makefile clean &> /dev/null
   ./make_fds.sh &> $FIREBOT_DIR/output/stage4b
}

check_compile_fds()
{
   # Check for errors in FDS compilation
   cd $FDS_SVNROOT/FDS_Compilation/${OPENMP}intel_${platform}_64
   if [ -e "fds_${OPENMP}intel_${platform}_64" ]
   then
      stage4a_success=true
   else
      echo "Errors from Stage 4a - Compile FDS release:" >> $ERROR_LOG
      cat $FIREBOT_DIR/output/stage4a >> $ERROR_LOG
      echo "" >> $ERROR_LOG
   fi

   # Check for compiler warnings/remarks
   # 'performing multi-file optimizations' and 'generating object file' are part of a normal compile
   if [[ `grep -A 5 -E 'warning|remark' ${FIREBOT_DIR}/output/stage4a | grep -v 'performing multi-file optimizations' | grep -v 'generating object file'` == "" ]]
   then
      # Continue along
      :
   else
      echo "Stage 4a warnings:" >> $WARNING_LOG
      grep -A 5 -E 'warning|remark' ${FIREBOT_DIR}/output/stage4a | grep -v 'performing multi-file optimizations' | grep -v 'generating object file'>> $WARNING_LOG
      echo "" >> $WARNING_LOG
   fi
}

check_compile_fds_mpi()
{
   # Check for errors in FDS compilation
   cd $FDS_SVNROOT/FDS_Compilation/mpi_intel_${platform}_64$IB
   if [ -e "fds_mpi_intel_${platform}_64$IB" ]
   then
      stage4b_success=true
   else
      echo "Errors from Stage 4b - Compile FDS release:" >> $ERROR_LOG
      cat $FIREBOT_DIR/output/stage4b >> $ERROR_LOG
      echo "" >> $ERROR_LOG
   fi

   # Check for compiler warnings/remarks
   # 'performing multi-file optimizations' and 'generating object file' are part of a normal compile
   if [[ `grep -A 5 -E 'warning|remark' ${FIREBOT_DIR}/output/stage4b | grep -v 'performing multi-file optimizations' | grep -v 'generating object file'| grep -v 'feupdateenv is not implemented'` == "" ]]
   then
      # Continue along
      :
   else
      echo "Stage 4b warnings:" >> $WARNING_LOG
      grep -A 5 -E 'warning|remark' ${FIREBOT_DIR}/output/stage4b | grep -v 'performing multi-file optimizations' | grep -v 'generating object file'| grep -v 'feupdateenv is not implemented' >> $WARNING_LOG
      echo "" >> $WARNING_LOG
   fi
}

#  ======================================
#  = Stage 5pre - Compile SMV utilities =
#  ======================================

compile_smv_utilities()
{
   echo "" > $FIREBOT_DIR/output/stage5pre
   if [ "$haveCC" == "1" ] ; then

   # smokeview libraries
   cd $FDS_SVNROOT/SMV/Build/LIBS/lib_${platform}_intel_64
   echo 'Building Smokeview libraries:' >> $FIREBOT_DIR/output/stage5pre 2>&1
   ./makelibs.sh >> $FIREBOT_DIR/output/stage5pre 2>&1

   # smokezip:
   cd $FDS_SVNROOT/Utilities/smokezip/intel_${platform}_64
   rm -f *.o smokezip_${platform}_64
   echo 'Compiling smokezip:' >> $FIREBOT_DIR/output/stage5pre 2>&1
   ./make_zip.sh >> $FIREBOT_DIR/output/stage5pre 2>&1
   echo "" >> $FIREBOT_DIR/output/stage5pre 2>&1
   
   # smokediff:
   cd $FDS_SVNROOT/Utilities/smokediff/intel_${platform}_64
   rm -f *.o smokediff_${platform}_64
   echo 'Compiling smokediff:' >> $FIREBOT_DIR/output/stage5pre 2>&1
   ./make_diff.sh >> $FIREBOT_DIR/output/stage5pre 2>&1
   echo "" >> $FIREBOT_DIR/output/stage5pre 2>&1
   
   # background:
   cd $FDS_SVNROOT/Utilities/background/intel_${platform}_32
   rm -f *.o background
   echo 'Compiling background:' >> $FIREBOT_DIR/output/stage5pre 2>&1
   ./make_background.sh >> $FIREBOT_DIR/output/stage5pre 2>&1
   
  # wind2fds:
   cd $FDS_SVNROOT/Utilities/wind2fds/intel_${platform}_64
   rm -f *.o wind2fds_${platform}_64
   echo 'Compiling wind2fds:' >> $FIREBOT_DIR/output/stage5pre 2>&1
   ./make_wind.sh >> $FIREBOT_DIR/output/stage5pre 2>&1
   echo "" >> $FIREBOT_DIR/output/stage5pre 2>&1

   fi
}

is_file_installed()
{
  program=$1
  notfound=`$program -help |& tail -1 |& grep "not found" | wc -l`
  if [ "$notfound" == "1" ] ; then
    stage5pre_success="0"
    echo "***error: $program not installed" >> $FIREBOT_DIR/output/stage5pre
  fi
}

check_smv_utilities()
{
   if [ "$haveCC" == "1" ] ; then
     # Check for errors in SMV utilities compilation
     cd $FDS_SVNROOT
     if [ -e "$FDS_SVNROOT/Utilities/smokezip/intel_${platform}_64/smokezip_${platform}_64" ]  && \
        [ -e "$FDS_SVNROOT/Utilities/smokediff/intel_${platform}_64/smokediff_${platform}_64" ]  && \
        [ -e "$FDS_SVNROOT/Utilities/wind2fds/intel_${platform}_64/wind2fds_${platform}_64" ]  && \
        [ -e "$FDS_SVNROOT/Utilities/background/intel_${platform}_32/background" ]
     then
        stage5pre_success="1"
     else
        stage5pre_success="0"
        echo "Errors from Stage 5pre - Compile SMV utilities:" >> $ERROR_LOG
        cat $FIREBOT_DIR/output/stage5pre >> $ERROR_LOG
        echo "" >> $ERROR_LOG
     fi
   else
     stage5pre_success="1"
     is_file_installed smokeview
     is_file_installed smokezip
     is_file_installed smokediff
     is_file_installed wind2fds
     is_file_installed background
     if [ "$stage5pre_success" == "0" ] ; then
        echo "Errors from Stage 5pre - Smokeview and utilities:" >> $ERROR_LOG
        stage5pre_success="1"
        cat $FIREBOT_DIR/output/stage5pre >> $ERROR_LOG
        echo "" >> $ERROR_LOG
     fi
   fi
}

#  ===================================================
#  = Stage 5 - Run verification cases (release mode) =
#  ===================================================

wait_verification_cases_release_end()
{
   # Scans qstat and waits for verification cases to end
   if [[ "$FIREBOT_QUEUE" == "none" ]]
   then
     while [[ `ps -u $USER -f | fgrep .fds | grep -v grep` != '' ]]; do
        JOBS_REMAINING=`ps -u $USER -f | fgrep .fds | grep -v grep | wc -l`
        echo "Waiting for ${JOBS_REMAINING} verification cases to complete." >> $FIREBOT_DIR/output/stage5
        TIME_LIMIT_STAGE="5"
        check_time_limit
        sleep 60
     done
   else
     while [[ `qstat -a | grep $(whoami) | grep $JOBPREFIX` != '' ]]; do
        JOBS_REMAINING=`qstat -a | grep $(whoami) | grep $JOBPREFIX | wc -l`
        echo "Waiting for ${JOBS_REMAINING} verification cases to complete." >> $FIREBOT_DIR/output/stage5
        TIME_LIMIT_STAGE="5"
        check_time_limit
        sleep 60
     done
   fi
}

run_verification_cases_release()
{
   # Start running all SMV verification cases
   cd $FDS_SVNROOT/Verification/scripts
   echo 'Running SMV verification cases:' >> $FIREBOT_DIR/output/stage5 2>&1
   ./Run_SMV_Cases.sh $USEINSTALL2 $RUN_OPENMP -q $FIREBOT_QUEUE >> $FIREBOT_DIR/output/stage5 2>&1

   # Wait for all verification cases to end
   wait_verification_cases_release_end
}

check_verification_cases_release()
{
   # Scan and report any errors in FDS verification cases
   cd $FDS_SVNROOT/Verification

   if [[ `grep 'Run aborted' -rI ${FIREBOT_DIR}/output/stage5` == "" ]] && \
      [[ `grep Segmentation -rI *` == "" ]] && \
      [[ `grep ERROR: -rI *` == "" ]] && \
      [[ `grep 'STOP: Numerical' -rI *` == "" ]] && \
      [[ `grep -A 20 forrtl -rI *` == "" ]]
   then
      stage5_success=true
   else
      grep 'Run aborted' -rI $FIREBOT_DIR/output/stage5 > $FIREBOT_DIR/output/stage5_errors
      grep Segmentation -rI * >> $FIREBOT_DIR/output/stage5_errors
      grep ERROR: -rI * >> $FIREBOT_DIR/output/stage5_errors
      grep 'STOP: Numerical' -rI * >> $FIREBOT_DIR/output/stage5_errors
      grep -A 20 forrtl -rI * >> $FIREBOT_DIR/output/stage5_errors
      
      echo "Errors from Stage 5 - Run verification cases (release mode):" >> $ERROR_LOG
      cat $FIREBOT_DIR/output/stage5_errors >> $ERROR_LOG
      echo "" >> $ERROR_LOG
      THIS_FDS_FAILED=1
   fi
   if [[ `grep 'Warning' -rI ${FIREBOT_DIR}/output/stage5` == "" ]] 
   then
      no_warnings=true
   else
      echo "Stage 5 warnings:" >> $WARNING_LOG
      grep 'Warning' -rI ${FIREBOT_DIR}/output/stage5 >> $WARNING_LOG
      echo "" >> $WARNING_LOG
   fi
}

#  ================================
#  = Stage 6a - Compile SMV debug =
#  ================================

compile_smv_db()
{
   if [ "$haveCC" == "1" ] ; then
   # Clean and compile SMV debug
   cd $FDS_SVNROOT/SMV/Build/intel_${platform}_64
   rm -f smokeview_${platform}_64_db
   ./make_smv_db.sh &> $FIREBOT_DIR/output/stage6a
   fi
}

check_compile_smv_db()
{
   if [ "$haveCC" == "1" ] ; then
   # Check for errors in SMV debug compilation
   cd $FDS_SVNROOT/SMV/Build/intel_${platform}_64
   if [ -e "smokeview_${platform}_64_db" ]
   then
      stage6a_success=true
   else
      echo "Errors from Stage 6a - Compile SMV debug:" >> $ERROR_LOG
      cat $FIREBOT_DIR/output/stage6a >> $ERROR_LOG
      echo "" >> $ERROR_LOG
   fi

   # Check for compiler warnings/remarks
   # grep -v 'feupdateenv ...' ignores a known FDS MPI compiler warning (http://software.intel.com/en-us/forums/showthread.php?t=62806)
   if [[ `grep -A 5 -E 'warning|remark' ${FIREBOT_DIR}/output/stage6a | grep -v 'feupdateenv is not implemented' | grep -v 'lcilkrts linked'` == "" ]]
   then
      # Continue along
      :
   else
      echo "Stage 6a warnings:" >> $WARNING_LOG
      grep -A 5 -E 'warning|remark' ${FIREBOT_DIR}/output/stage6a | grep -v 'feupdateenv is not implemented' | grep -v 'lcilkrts linked' >> $WARNING_LOG
      echo "" >> $WARNING_LOG
   fi
   fi
}

#  =============================================
#  = Stage 6b - Make SMV pictures (debug mode) =
#  =============================================

make_smv_pictures_db()
{
   # Run Make SMV Pictures script (debug mode)
   cd $FDS_SVNROOT/Verification/scripts
   ./Make_SMV_Pictures.sh $USEINSTALL -d 2>&1 | grep -v FreeFontPath &> $FIREBOT_DIR/output/stage6b
}

check_smv_pictures_db()
{
   # Scan and report any errors in make SMV pictures process
   cd $FIREBOT_DIR
   if [[ `grep -I -E "Segmentation|Error" $FIREBOT_DIR/output/stage6b` == "" ]]
   then
      stage6b_success=true
   else
      cp $FIREBOT_DIR/output/stage6b $FIREBOT_DIR/output/stage6b_errors

      echo "Errors from Stage 6b - Make SMV pictures (debug mode):" >> $ERROR_LOG
      cat $FIREBOT_DIR/output/stage6b_errors >> $ERROR_LOG
      echo "" >> $ERROR_LOG
   fi
}

#  ==================================
#  = Stage 6c - Compile SMV release =
#  ==================================

compile_smv()
{
   if [ "$haveCC" == "1" ] ; then
   # Clean and compile SMV
   cd $FDS_SVNROOT/SMV/Build/intel_${platform}_64
   rm -f smokeview_${platform}_64
   ./make_smv.sh &> $FIREBOT_DIR/output/stage6c
   fi
}

check_compile_smv()
{
   if [ "$haveCC" == "1" ] ; then
   # Check for errors in SMV release compilation
   cd $FDS_SVNROOT/SMV/Build/intel_${platform}_64
   if [ -e "smokeview_${platform}_64" ]
   then
      stage6c_success=true
   else
      echo "Errors from Stage 6c - Compile SMV release:" >> $ERROR_LOG
      cat $FIREBOT_DIR/output/stage6c >> $ERROR_LOG
      echo "" >> $ERROR_LOG
   fi

   # Check for compiler warnings/remarks
   # grep -v 'feupdateenv ...' ignores a known FDS MPI compiler warning (http://software.intel.com/en-us/forums/showthread.php?t=62806)
   if [[ `grep -A 5 -E 'warning|remark' ${FIREBOT_DIR}/output/stage6c | grep -v 'feupdateenv is not implemented' | grep -v 'lcilkrts linked'` == "" ]]
   then
      # Continue along
      :
   else
      echo "Stage 6c warnings:" >> $WARNING_LOG
      grep -A 5 -E 'warning|remark' ${FIREBOT_DIR}/output/stage6c | grep -v 'feupdateenv is not implemented' | grep -v 'lcilkrts linked' >> $WARNING_LOG
      echo "" >> $WARNING_LOG
   fi
   fi
}

#  ===============================================
#  = Stage 6d - Make SMV pictures (release mode) =
#  ===============================================

make_smv_pictures()
{
   # Run Make SMV Pictures script (release mode)
   cd $FDS_SVNROOT/Verification/scripts
   ./Make_SMV_Pictures.sh $USEINSTALL 2>&1 | grep -v FreeFontPath &> $FIREBOT_DIR/output/stage6d
}

check_smv_pictures()
{
   # Scan and report any errors in make SMV pictures process
   cd $FIREBOT_DIR
   if [[ `grep -I -E "Segmentation|Error" $FIREBOT_DIR/output/stage6d` == "" ]]
   then
      stage6d_success=true
   else
      cp $FIREBOT_DIR/output/stage6d  $FIREBOT_DIR/output/stage6d_errors

      echo "Errors from Stage 6d - Make SMV pictures (release mode):" >> $ERROR_LOG
      cat $FIREBOT_DIR/output/stage6d >> $ERROR_LOG
      echo "" >> $ERROR_LOG
   fi
}

#  ===============================================
#  = Stage 6e - Make SMV movies (release mode) =
#  ===============================================

make_smv_movies()
{
   cd $FDS_SVNROOT/Verification
   scripts/Make_SMV_Movies.sh 2>&1  &> $FIREBOT_DIR/output/stage6e
}

check_smv_movies()
{
   cd $FIREBOT_DIR
   if [[ `grep -I -E "Segmentation|Error" $FIREBOT_DIR/output/stage6e` == "" ]]
   then
      stage6e_success=true
   else
      cp $FIREBOT_DIR/output/stage6e  $FIREBOT_DIR/output/stage6e_errors

      echo "Errors from Stage 6e - Make SMV movies " >> $ERROR_LOG
      cat $FIREBOT_DIR/output/stage6e >> $ERROR_LOG
      echo "" >> $ERROR_LOG
   fi
}

#  ======================================
#  = Stage 7 - FDS run time statistics =
#  ======================================

generate_timing_stats()
{
   cd $FDS_SVNROOT/Verification/scripts/
   export RUNCFAST="$FDS_SVNROOT/Verification/scripts/copyout.sh"
   export RUNFDS="$FDS_SVNROOT/Verification/scripts/copyout.sh"
   export RUNWFDS="$FDS_SVNROOT/Verification/scripts/copyout.sh"
   export RUNTFDS="$FDS_SVNROOT/Verification/scripts/copyout.sh"

   cd $FDS_SVNROOT/Verification
   scripts/SMV_Cases.sh

   cd $FDS_SVNROOT/Utilities/Scripts
   ./fds_timing_stats.sh smokebot
}

archive_timing_stats()
{
   cd $FDS_SVNROOT/Utilities/Scripts
   cp fds_timing_stats.csv "$FIREBOT_DIR/history/${SVN_REVISION}_timing.csv"
}

#  ==================================
#  = Stage 8 - Build FDS-SMV Guides =
#  ==================================

check_guide()
{
   # Scan and report any errors in build process for guides
   SMOKEBOT_MANDIR=/var/www/html/smokebot/manuals/
   FIREBOT_MANDIR=/var/www/html/firebot/manuals/
   cd $FIREBOT_DIR
   if [[ `grep "! LaTeX Error:" -I $1` == "" ]]
   then
      if [ -d $SMOKEBOT_MANDIR ] ; then
        cp $2 $SMOKEBOT_MANDIR/.
      fi
      if [ -d $SMV_Summary/manuals ] ; then
        cp $2 $SMV_Summary/manuals/.
      fi
      if [ -d $FIREBOT_MANDIR ] ; then
        cp $2 $FIREBOT_MANDIR/.
      fi
      cp $2 $GUIDE_DIR/.
   else
      echo "Errors from Stage 8 - Build FDS-SMV Guides:" >> $ERROR_LOG
      echo $3 >> $ERROR_LOG
      grep "! LaTeX Error:" -I $1 >> $ERROR_LOG
      echo "" >> $ERROR_LOG
   fi

   # Check for LaTeX warnings (undefined references or duplicate labels)
   if [[ `grep -E "undefined|multiply defined|multiply-defined" -I ${1}` == "" ]]
   then
      # Continue along
      :
   else
      echo "Stage 8 warnings:" >> $WARNING_LOG
      echo $3 >> $WARNING_LOG
      grep -E "undefined|multiply defined|multiply-defined" -I $1 >> $WARNING_LOG
      echo "" >> $WARNING_LOG
   fi
}

make_smv_user_guide()
{
   # Build SMV User Guide
   cd $FDS_SVNROOT/Manuals/SMV_User_Guide
   export TEXINPUTS=".:../LaTeX_Style_Files:"
   pdflatex -interaction nonstopmode SMV_User_Guide &> $FIREBOT_DIR/output/stage8_smv_user_guide
   bibtex SMV_User_Guide &> $FIREBOT_DIR/output/stage8_smv_user_guide
   pdflatex -interaction nonstopmode SMV_User_Guide &> $FIREBOT_DIR/output/stage8_smv_user_guide
   pdflatex -interaction nonstopmode SMV_User_Guide &> $FIREBOT_DIR/output/stage8_smv_user_guide

   # Check guide for completion and copy to website if successful
   check_guide $FIREBOT_DIR/output/stage8_smv_user_guide $FDS_SVNROOT/Manuals/SMV_User_Guide/SMV_User_Guide.pdf 'SMV User Guide'
}

make_smv_technical_guide()
{
   # Build SMV Technical Guide
   cd $FDS_SVNROOT/Manuals/SMV_Technical_Reference_Guide
   export TEXINPUTS=".:../LaTeX_Style_Files:"
   pdflatex -interaction nonstopmode SMV_Technical_Reference_Guide &> $FIREBOT_DIR/output/stage8_smv_technical_guide
   bibtex SMV_Technical_Reference_Guide &> $FIREBOT_DIR/output/stage8_smv_technical_guide
   pdflatex -interaction nonstopmode SMV_Technical_Reference_Guide &> $FIREBOT_DIR/output/stage8_smv_technical_guide
   pdflatex -interaction nonstopmode SMV_Technical_Reference_Guide &> $FIREBOT_DIR/output/stage8_smv_technical_guide

   # Check guide for completion and copy to website if successful
   check_guide $FIREBOT_DIR/output/stage8_smv_technical_guide $FDS_SVNROOT/Manuals/SMV_Technical_Reference_Guide/SMV_Technical_Reference_Guide.pdf 'SMV Technical Reference Guide'
}

make_smv_verification_guide()
{
   # Build SMV Verification Guide
   cd $FDS_SVNROOT/Manuals/SMV_Verification_Guide
   export TEXINPUTS=".:../LaTeX_Style_Files:"
   pdflatex -interaction nonstopmode SMV_Verification_Guide &> $FIREBOT_DIR/output/stage8_smv_verification_guide
   bibtex SMV_Verification_Guide &> $FIREBOT_DIR/output/stage8_smv_verification_guide
   pdflatex -interaction nonstopmode SMV_Verification_Guide &> $FIREBOT_DIR/output/stage8_smv_verification_guide
   pdflatex -interaction nonstopmode SMV_Verification_Guide &> $FIREBOT_DIR/output/stage8_smv_verification_guide

   # Check guide for completion and copy to website if successful
   check_guide $FIREBOT_DIR/output/stage8_smv_verification_guide $FDS_SVNROOT/Manuals/SMV_Verification_Guide/SMV_Verification_Guide.pdf 'SMV Verification Guide'
}

#  =====================================================
#  = Build status reporting - email and save functions =
#  =====================================================

save_build_status()
{
   cd $FIREBOT_DIR
   # Save status outcome of build to a text file
   if [[ -e $WARNING_LOG && -e $ERROR_LOG ]]
   then
     cat "" >> $ERROR_LOG
     cat $WARNING_LOG >> $ERROR_LOG
     echo "Build failure and warnings for Revision ${SVN_REVISION}." > "$FIREBOT_DIR/history/${SVN_REVISION}.txt"
     cat $ERROR_LOG > "$FIREBOT_DIR/history/${SVN_REVISION}_errors.txt"
     touch output/status_errors_and_warnings

   # Check for errors only
   elif [ -e $ERROR_LOG ]
   then
      echo "Build failure for Revision ${SVN_REVISION}." > "$FIREBOT_DIR/history/${SVN_REVISION}.txt"
      cat $ERROR_LOG > "$FIREBOT_DIR/history/${SVN_REVISION}_errors.txt"
      touch output/status_errors

   # Check for warnings only
   elif [ -e $WARNING_LOG ]
   then
      echo "Revision ${SVN_REVISION} has warnings." > "$FIREBOT_DIR/history/${SVN_REVISION}.txt"
      cat $WARNING_LOG > "$FIREBOT_DIR/history/${SVN_REVISION}_warnings.txt"
      touch output/status_warnings

   # No errors or warnings
   else
      echo "Build success! Revision ${SVN_REVISION} passed all build tests." > "$FIREBOT_DIR/history/${SVN_REVISION}.txt"
      touch output/status_success
   fi
}

email_build_status()
{
   if [[ "$THIS_FDS_FAILED" == "1" ]] ; then
     mailTo=$mailToFDS
   fi
   echo $THIS_FDS_FAILED>$FDS_STATUS_FILE
   stop_time=`date`
   echo "-------------------------------" > $TIME_LOG
   echo "      host: $hostname " >> $TIME_LOG
   echo "start time: $start_time " >> $TIME_LOG
   echo " stop time: $stop_time " >> $TIME_LOG
   echo "   results (private): http://blaze.nist.gov/VV/SMV2" >> $TIME_LOG
   echo "   results (public) :  https://googledrive.com/host/0B-W-dkXwdHWNN3N2eG92X2taRFk/index.html" >> $TIME_LOG
   echo "   manuals (private): http://blaze.nist.gov/smokebot" >> $TIME_LOG
   echo "   manuals (public) : https://drive.google.com/folderview?id=0B_wB1pJL2bFQaDJaOFNnUDR4LXM#list" >> $TIME_LOG
  if [[ $THIS_SMVSVN != $LAST_SMVSVN ]] ; then
    cat $SVN_SMVLOG >> $TIME_LOG
  fi
  if [[ $THIS_FDSSVN != $LAST_FDSSVN ]] ; then
    cat $SVN_FDSLOG >> $TIME_LOG
  fi
   echo "-------------------------------" >> $TIME_LOG
   cd $FIREBOT_DIR
   # Check for warnings and errors
   if [[ -e $WARNING_LOG && -e $ERROR_LOG ]]
   then
     cat $TIME_LOG >> $ERROR_LOG
     cat $TIME_LOG >> $WARNING_LOG
     # Send email with failure message and warnings, body of email contains appropriate log file
     mail -s "smokebot build failure and warnings on ${hostname}. Revision ${SVN_REVISION}." $mailTo < $ERROR_LOG > /dev/null

   # Check for errors only
   elif [ -e $ERROR_LOG ]
   then
     cat $TIME_LOG >> $ERROR_LOG
      # Send email with failure message, body of email contains error log file
      mail -s "smokebot build failure on ${hostname}. Revision ${SVN_REVISION}." $mailTo < $ERROR_LOG > /dev/null

   # Check for warnings only
   elif [ -e $WARNING_LOG ]
   then
     cat $TIME_LOG >> $WARNING_LOG
      # Send email with success message, include warnings
      mail -s "smokebot build success with warnings on ${hostname}. Revision ${SVN_REVISION}." $mailTo < $WARNING_LOG > /dev/null

   # No errors or warnings
   else
      # Send empty email with success message
      mail -s "smokebot build success on ${hostname}! Revision ${SVN_REVISION}." $mailTo < $TIME_LOG > /dev/null
   fi
}

# if -a option is invoked, only proceed running smokebot if the
# smokeview or FDS source has changed

if [[ $RUNAUTO == "y" ]] ; then
  run_auto
fi

#  ============================
#  = Primary script execution =
#  ============================

hostname=`hostname`
start_time=`date`
clean_smokebot_history

### Stage 0 ###
update_and_compile_cfast

### Stage 1 ###
clean_svn_repo
do_svn_checkout
check_svn_checkout

### Stage 2a ###
compile_fds_db
check_compile_fds_db

### Stage 2b ###
compile_fds_mpi_db
check_compile_fds_mpi_db

### Stage 3 ###
if [[ $stage2a_success && "$RUNDEBUG" == "1" ]] ; then
   run_verification_cases_debug
   check_verification_cases_debug
fi

### Stage 4a ###
if [[ $stage2a_success ]] ; then
   compile_fds
   check_compile_fds
fi

### Stage 4b ###
if [[ $stage2b_success ]] ; then
   compile_fds_mpi
   check_compile_fds_mpi
fi

### Stage 5pre ###
compile_smv_utilities
check_smv_utilities

### Stage 5 ###
if [[ $stage4a_success && $stage4b_success ]] ; then
   run_verification_cases_release
   check_verification_cases_release
fi

### Stage 6a ###
compile_smv_db
check_compile_smv_db

### Stage 6b ###
if [[ $stage4a_success && $stage4b_success && $stage6a_success && "$RUNDEBUG" == "1" ]] ; then
  make_smv_pictures_db
  check_smv_pictures_db
fi

### Stage 6c ###
compile_smv
check_compile_smv

### Stage 6d ###
if [[ $stage4a_success && $stage4b_success && $stage6c_success ]] ; then
  make_smv_pictures
  check_smv_pictures
fi

### Stage 6e ###
if [ "$MAKEMOVIES" == "1" ]
then
  make_smv_movies
  check_smv_movies
fi

### Stage 7 ###
if [[ $stage4a_success && $stage4b_success ]] ; then
  generate_timing_stats
  archive_timing_stats
fi

### Stage 8 ###
if [[ $stage4a_success && $stage4b_success && $stage6d_success ]] ; then
  make_smv_user_guide
  make_smv_technical_guide
  make_smv_verification_guide
fi

### Report results ###
set_files_world_readable
save_build_status
email_build_status
