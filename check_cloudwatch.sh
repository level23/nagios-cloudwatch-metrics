#!/usr/bin/env bash

# Exit codes
STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3

type jq >/dev/null 2>&1 || { echo >&2 "I require jq but it's not installed. Aborting."; exit 1; }
type aws >/dev/null 2>&1 || { echo >&2 "I require awscli but it's not installed. Aborting."; exit 1; }
type bc >/dev/null 2>&1 || { echo >&2 "I require bc but it's not installed. Aborting."; exit 1; }

usage()
{
cat << EOF
usage: $0 [options]

This script checks AWS cloudwatch metrics. This script is meant for Nagios.

We assume that the binary JQ is installed. Also we assume that the AWS CLI binary is installed and that the
credentials are set up for the user who is executing this script.

OPTIONS:
    -h or --help     Show this message

    -v or --verbose  Optional: Show verbose output

    --profile=x      Optional: Which AWS profile should be used to connect to aws?

    --namespace=x    Required: Enter the AWS namespace where you want to check your metrics for. The "AWS/" prefix can be
                     left out. Example: "CloiudFront", "EC2" or "Firehose".
                     More information: http://docs.aws.amazon.com/AmazonCloudWatch/latest/DeveloperGuide/aws-namespaces.html

    --mins=x         Required: Supply the minutes (time window) of which you want to check the AWS metrics. We will fetch the data
                     between NOW-%mins and NOW.

    --region=x       Required: Enter the AWS region which we need to use. For example: "eu-west-1"

    --metric=x       Required: The metric name which you want to check. For example "IncomingBytes"

    --statistics=x   Required: The statistics which you want to fetch.
                     Possible values: Sum, Average, Maximum, Minimum, SampleCount
                     Default: Average

    --dimensions=x   Required: The dimensions which you want to fetch.
                     Examples:
                        Name=DBInstanceIdentifier,Value=i-1235534
                        Name=DeliveryStreamName,Value=MyStream
                     See also: http://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/cloudwatch_concepts.html#dimension-combinations

    --warning=x:x    Required: The warning value. You can supply min:max or just min value. If the fetched data is lower
                     then the minimum, or higher then the maxmimum, we will raise a warning.
                     If you only want a max check, set min to 0. Example: 0:20 will raise when the value is higher then 20

    --critical=x:x   Required: The critical value. You can supply min:max or just min value. If the fetched data is lower
                     then the minimum, or higher then the maxmimum, we will raise a critical.
                     If you only want a max check, set min to 0. Example: 0:20 will raise when the value is higher then 20



#######################
#
# Example usage:
#
# Description here
# $0 --region=eu-west-1 \
#    --namespace="Firehose" \
#    --metric="IncomingBytes" \
#    --statistics="Average" \
#    --mins=15 \
#    --dimensions="Name=DeliveryStreamName,Value=Visits-To-Redshift" \
#    --warning=100 \
#    --critical=50
#    --verbose
#
########################

EOF
}

#
# Use some fancy colors, see
# @http://stackoverflow.com/a/5947802/1351312
#
function error()
{
	RED='\033[0;31m'
	NC='\033[0m' # No Color
	echo -e "${RED}${1}${NC}";
}

# Display verbose output if wanted
#
function verbose
{
    if [[ ${VERBOSE} -eq 1 ]];
    then
        echo $1;
    fi
}

#
# Check if there are any parameters given
#
if [ $# -eq 0 ]
then
    usage;
    exit ${STATE_UNKNOWN};
fi

PROFILE=""
NAMESPACE=""
MINUTES=0
START_TIME=""
END_TIME=""
SECONDS=0
REGION=""
METRIC=""
STATISTICS="Average"
VERBOSE=0
DIMENSIONS=""
WARNING=""
CRITICAL=""
EXIT=0
WARNING_MIN=0
WARNING_MAX=0
CRITICAL_MIN=0
CRITICAL_MAX=0

#
# Awesome parameter parsing, see http://stackoverflow.com/questions/192249/how-do-i-parse-command-line-arguments-in-bash
#
for i in "$@"
do
case ${i} in
	--profile=* )
		PROFILE="${i#*=}"
		shift ;
		;;

	--namespace=* )
		NAMESPACE="AWS/${i#*=}"
		shift ;
		;;

	--mins=* )
	    MINUTES="${i#*=}"

	    unamestr=`uname`

        # Create files to compare against
	    if [[ "$unamestr" == 'Darwin' ]]; then
	        START_TIME=$(date -v-${MINUTES}M -u +'%Y-%m-%dT%H:%M:%S')
	    else
	        START_TIME=$(date -u +'%Y-%m-%dT%H:%M:%S' -d "-${MINUTES} minutes")
	    fi

        END_TIME=$(date -u +'%Y-%m-%dT%H:%M:00')
        SECONDS=$((60 * ${MINUTES}));
	    shift ;
	    ;;

	--region=* )
		REGION="${i#*=}"
		shift ;
		;;

	--metric=* )
		METRIC="${i#*=}"
		shift ;
		;;

	--statistics=* )
		STATISTICS="${i#*=}"
		shift ;
		;;

	-v | --verbose )
		VERBOSE=1
		shift ;
		;;

	--dimensions=* )
	    DIMENSIONS="${i#*=}"
		shift ;
		;;

	--warning=* )
	    WARNING="${i#*=}"
		shift ;
		;;

	--critical=* )
	    CRITICAL="${i#*=}"
		shift ;
		;;

	help | --help | -h)
		usage ;
		exit ${STATE_UNKNOWN};
		;;

	*)
		usage ;
		;;
	esac
done

#
# Validation
#

if [[ "${NAMESPACE}" == "" ]];
then
    error "You have to supply a namespace!";
    usage;
    exit ${STATE_UNKNOWN};
fi;

if [[ ${MINUTES} -le 0 ]];
then
    error "You have to supply a time range (minutes)";
    usage;
    exit ${STATE_UNKNOWN};
fi;

if [[ "${REGION}" == "" ]];
then
    error "You have to supply a region!";
    usage;
    exit ${STATE_UNKNOWN};
fi;

if [[ "${DIMENSIONS}" == "" ]];
then
    error "You have to supply dimensions!";
    usage;
    exit ${STATE_UNKNOWN};
fi;

if [[ "${METRIC}" == "" ]];
then
    error "You have to supply a metric!";
    usage;
    exit ${STATE_UNKNOWN};
fi;

if [[ "${STATISTICS}" != "SampleCount" ]] && [[ "${STATISTICS}" != "Average" ]] && [[ "${STATISTICS}" != "Sum" ]] && [[ "${STATISTICS}" != "Minimum" ]] && [[ "${STATISTICS}" != "Maximum" ]] ;
then
    error "You have to supply a statistics value";
    error "Possible values: Sum, Average, Maximum, Minimum, SampleCount";
    usage;
    exit ${STATE_UNKNOWN};
fi;

if [[ ! "${WARNING}" =~ ^[0-9\.]+(:[0-9\.]*)?$ ]];
then
    error "Warning should be a number or number:number format!";
    exit ${STATE_UNKNOWN};
fi

if [[ ! "${CRITICAL}" =~ ^[0-9\.]+(:[0-9\.]*)?$ ]];
then
    error "Critical should be a number or number:number format!";
    exit ${STATE_UNKNOWN};
fi

if [[ "${WARNING}" == *":"* ]];
then
  WARNING_MIN=$(echo "${WARNING}" | awk -F':' '{print $1}' );
  WARNING_MAX=$(echo "${WARNING}" | awk -F':' '{print $2}' );
else
  WARNING_MIN="${WARNING}";
fi

if [[ "${CRITICAL}" == *":"* ]];
then
  CRITICAL_MIN=$(echo "${CRITICAL}" | awk -F':' '{print $1}' );
  CRITICAL_MAX=$(echo "${CRITICAL}" | awk -F':' '{print $2}' );
else
  CRITICAL_MIN="${CRITICAL}";
fi


verbose "Namespace: ${NAMESPACE}";
verbose "Start time: ${START_TIME}";
verbose "Metric name: ${METRIC}";
verbose "Stop time: ${END_TIME}";
verbose "Minutes window: ${MINUTES}";
verbose "Period (Seconds): ${SECONDS}";
verbose "Demensions: ${DIMENSIONS}";

COMMAND="aws cloudwatch get-metric-statistics"
COMMAND="$COMMAND --region ${REGION}"
COMMAND="$COMMAND --namespace ${NAMESPACE}";
COMMAND="$COMMAND --metric-name ${METRIC}";
COMMAND="$COMMAND --output json";
COMMAND="$COMMAND --start-time ${START_TIME}";
COMMAND="$COMMAND --end-time ${END_TIME}";
COMMAND="$COMMAND --period ${SECONDS}";
COMMAND="$COMMAND --statistics ${STATISTICS}";
COMMAND="$COMMAND --dimensions ${DIMENSIONS}";

if [[ "$PROFILE" != "" ]];
then
  COMMAND="$COMMAND --profile $PROFILE";
fi

verbose "COMMAND: $COMMAND";
verbose "----------------";

RESULT=$(${COMMAND});
METRIC_VALUE=$(echo ${RESULT} | jq ".Datapoints[0].${STATISTICS}")
UNIT=$(echo ${RESULT} | jq -r ".Datapoints[0].Unit")
verbose "Raw result: ${RESULT}";
verbose "Unit: ${UNIT}";
DESCRIPTION=$(echo ${RESULT} | jq ".Label")

verbose "Min Warning: ${WARNING_MIN}";
verbose "Max Warning: ${WARNING_MAX}";
verbose "";
verbose "Min Critical: ${CRITICAL_MIN}";
verbose "Max Critical: ${CRITICAL_MAX}";
verbose "";

verbose "Metric value: ${METRIC_VALUE}";


MESSAGE=""
if [[ "${CRITICAL_MIN}" != "0" ]] && [[ 1 -eq "$(echo "${METRIC_VALUE} < ${CRITICAL_MIN}" | bc)" ]]; then
    MESSAGE="Critical: ${METRIC_VALUE} is less then ${CRITICAL_MIN}"
    EXIT=${STATE_CRITICAL};
elif [[ "${CRITICAL_MAX}" != "0" ]] && [[ 1 -eq "$(echo "${METRIC_VALUE} > ${CRITICAL_MAX}" | bc)" ]]; then
    MESSAGE="Critical: ${METRIC_VALUE} is more then ${CRITICAL_MAX}"
    EXIT=${STATE_CRITICAL};
elif [[ "${WARNING_MIN}" != "0" ]] && [[ 1 -eq "$(echo "${METRIC_VALUE} < ${WARNING_MIN}" | bc)" ]]; then
    MESSAGE="Warning: ${METRIC_VALUE} is less then ${WARNING_MIN}"
    EXIT=${STATE_WARNING};
elif [[ "${WARNING_MAX}" != "0" ]] && [[ 1 -eq "$(echo "${METRIC_VALUE} > ${WARNING_MAX}" | bc)" ]]; then
    MESSAGE="Warning: ${METRIC_VALUE} is more then ${WARNING_MAX}"
    EXIT=${STATE_WARNING};
else
    MESSAGE="All ok. "
    EXIT=${STATE_OK};
fi

BODY="${DIMENSIONS} ${METRIC} (${MINUTES} min ${STATISTICS}): ${METRIC_VALUE} ${UNIT} - ${MESSAGE}"

verbose "${BODY}"

case ${EXIT} in
  ${STATE_OK})
    printf "OK - ${BODY}"
    exit ${EXIT}
    ;;
  ${STATE_WARNING})
    echo "WARNING - ${BODY}"
    exit ${EXIT}
    ;;
  ${STATE_CRITICAL})
    echo "CRITICAL - ${BODY}"
    exit ${EXIT}
    ;;
  *)
    echo "UNKNOWN - ${BODY}"
    exit ${STATE_UNKNOWN};
    ;;
esac