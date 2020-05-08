#!/bin/bash

# Set up the routing needed for the simulation
echo "Setting up the simulation with setup.sh"
/setup.sh
echo "Setup.sh completed"

# The following variables are available for use:
# - ROLE contains the role of this execution context, client or server
# - SERVER_PARAMS contains user-supplied command line parameters
# - CLIENT_PARAMS contains user-supplied command line parameters

RET=0
# Verify that the test case is supported 
case "$TESTCASE" in
        "versionnegotiation") RET=0 ;;
        "handshake") RET=0 ;;
        "transfer") RET=0 ;;
        "retry") RET=0 ;;
        "resumption") RET=0 ;;
        "zerortt") RET=0 ;;
        "http3") RET=0 ;;
        "multiconnect") RET=0 ;;
        *) echo "Unsupported test case: $TESTCASE"; exit 127 ;;
esac

if [ "$ROLE" == "client" ]; then
    # Wait for the simulator to start up.
    echo "Waiting for  the simulator to start"
    /wait-for-it.sh sim:57832 -s -t 30
    echo "Starting picoquic client for test: $TESTCASE"
    # setup default parameters
    LOGFILE="/logs/test_log.txt"
    TEST_PARAMS="$CLIENT_PARAMS -L -l $LOGFILE -b /logs/client_bin.log -o /downloads"
    if [ "$TESTCASE" == "http3" ]; then
        TEST_PARAMS="$TEST_PARAMS -a h3-27";
    fi
    if [ "$TESTCASE" == "versionnegotiation" ]; then
        TEST_PARAMS="$TEST_PARAMS -v 5a6a7a8a";
    else
        TEST_PARAMS="$TEST_PARAMS -v ff00001b";
    fi
    echo "Starting picoquic client ..."
    if [ ! -z "$REQUESTS" ]; then
        # pull requests out of param
        echo "Requests: " $REQUESTS
        for REQ in $REQUESTS; do
            FILE=`echo $REQ | cut -f4 -d'/'`
            echo "parsing <$REQ> as <$FILE>"
            FILELIST=${FILELIST}"-:/"${FILE}";"
        done

        if [ "$TESTCASE" == "resumption" ] ||
           [ "$TESTCASE" == "zerortt" ] ; then
            FILE1=`echo $FILELIST | cut -f1 -d";"`
            FILE2=`echo $FILELIST | cut -f2- -d";"`
            L1="/logs/first_log.txt"
            L2="/logs/second_log.txt"
            echo "File1: $FILE1"
            echo "File2: $FILE2"
            rm *.bin
            echo "/picoquic/picoquicdemo $TEST_PARAMS server 443 $FILE1"
            /picoquic/picoquicdemo $TEST_PARAMS server 443 $FILE1
            if [ $? != 0 ]; then
                RET=1
                echo "First call to picoquicdemo failed"
            else
                mv $LOGFILE $L1
                /picoquic/picolog -f qlog -o /logs/qlog /logs/client_log.bin
                echo "/picoquic/picoquicdemo $TEST_PARAMS server 443 $FILE2"
                /picoquic/picoquicdemo $TEST_PARAMS server 443 $FILE2
                if [ $? != 0 ]; then
                    RET=1
                    echo "Second call to picoquicdemo failed"
                fi
                mv $LOGFILE $L2
            fi
            /picoquic/picolog -f qlog -o /logs/qlog /logs/client_log.bin
        elif [ "$TESTCASE" == "multiconnect" ]; then
            for CREQ in $REQUESTS; do
                CFILE=`echo $CREQ | cut -f4 -d'/'`
                CFILEX="/$CFILE"
                echo "/picoquic/picoquicdemo $TEST_PARAMS server 443 $CFILEX"
                /picoquic/picoquicdemo $TEST_PARAMS server 443 $CFILEX
                if [ $? != 0 ]; then
                    RET=1
                    echo "Call to picoquicdemo failed"
                fi
                /picoquic/picolog -f qlog -o /logs/qlog /logs/client_log.bin
                MCLOG="/logs/mc-$CFILE.txt"
                echo "mv $LOGFILE  $MCLOG"
                mv $LOGFILE $MCLOG
            done
        else
            if [ "$TESTCASE" == "retry" ]; then
                rm *.bin
            fi
            /picoquic/picoquicdemo $TEST_PARAMS server 443 $FILELIST
            if [ $? != 0 ]; then
                RET=1
                echo "Call to picoquicdemo failed"
            fi
            /picoquic/picolog -f qlog -o /logs/qlog /logs/client_log.bin
        fi
    fi

### Server side ###
elif [ "$ROLE" == "server" ]; then
    echo "Starting picoquic server for test:" $TESTCASE
    TEST_PARAMS="$SERVER_PARAMS -w ./www -L -l /logs/server_log.txt"
    TEST_PARAMS="$TEST_PARAMS -b /logs/server_log.bin" 
    TEST_PARAMS="$TEST_PARAMS -k picoquic/certs/key.pem"
    TEST_PARAMS="$TEST_PARAMS -c picoquic/certs/cert.pem"
    TEST_PARAMS="$TEST_PARAMS -p 443"
    ls /www
    case "$TESTCASE" in
        "retry") TEST_PARAMS="$TEST_PARAMS -r" ;;
        *) ;;
    esac
    echo "Starting picoquic server ..."
    echo "TEST_PARAMS: $TEST_PARAMS"
    picoquic/picoquicdemo $TEST_PARAMS
    if [ $? != 0 ]; then
        RET=1
        echo "Could not start picoquicdemo"
    fi
    /picoquic/picolog -f qlog -o /logs/qlog /logs/server_log.bin
else
    echo "Unexpected role: $ROLE"
    RET=1
fi
exit $RET
