# Nagios Cloudwatch Metrics plugin

This plugin allows you to check certain AWS Cloudwatch metrics and set alerts on certain values.
 
The script is written in bash. It is tested on OSX and Ubuntu 16.04. 

This plugin fetches the data from X minutes back until now. 

### Dependencies ###

To run this script you should have installed the following packages:
  - jq - json processor
  - awscli - AWS command line interface
  - bc - used for working with floating point numbers
  
We assume that the user who execute this script has configured his account so that he/she can connect to Amazon.

If not, please do this first. See here for more info: 
http://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html

### Parameters ###

See the help message:
```bash
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
    
    --timeout=x      Optional: Specify the max duration in seconds of this script.
                     When the timeout is reached, we will return a UNKNOWN alert status.

    --statistics=x   Required: The statistics which you want to fetch.
                     Possible values: Sum, Average, Maximum, Minimum, SampleCount
                     Default: Average

    --dimensions=x   Required: The dimensions which you want to fetch.
                     Examples:
                        Name=DBInstanceIdentifier,Value=i-1235534
                        Name=DeliveryStreamName,Value=MyStream
                     See also: http://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/cloudwatch_concepts.html#dimension-combinations

    --warning=x:x    Required: The warning threshold. You can supply min:max or just max value. Use the format: [@]min:max
                     When no minimal value is given, a default min value of 0 is used.
                     By default we will raise a warning alert when the value is outside the given range. You can start the range
                     with an @ sign to change this logic. We then will alert when the value is inside the range.
                     See below for some examples.

    --critical=x:x   Required: The critical threshold. You can supply min:max or just max value. Use the format: [@]min:max
                     When no minimal value is given, a default min value of 0 is used.
                     By default we will raise a critical alert when the value is outside the given range. You can start the range
                     with an @ sign to change this logic. We then will alert when the value is inside the range.
                     See below for some examples.
                     
    --default="x"    When no data points are returned, it could be because there is no data. By default this script will return
                     the nagios state UNKNOWN. You could also supply a default value here (like 0). In that case we will work
                     with that value when no data points are returned.
                     


Example threshold values:

--critical=10
We will raise an alert when the value is < 0 or > 10

--critical=5:10
We will raise an alert when the value is < 5 or > 10

--critical=@5:10
We will raise an alert when the value is >= 5 and <= 10

--critical=~:10
We will raise an alert when the value is > 10 (there is no lower limit)

--critical=10:~
We will raise an alert when the value is < 10 (there is no upper limit)

--critical=10:
(Same as above) We will raise an alert when the value is < 10 (there is no upper limit)

--critical=@1:~
Alert when the value is >= 1. Zero is OK.


See for more info: https://www.monitoring-plugins.org/doc/guidelines.html#THRESHOLDFORMAT
```

### AWS Credentials ###

This plugin uses the AWS Command Line Interface to retrieve the metrics data from Amazon. To make this plugin work you 
should make sure that the user who execute's this plugin can use the Amazon CLI.
  
The AWS CLI will automatically search for your credentials (access key id and secret access key) in a few places. 
See also here: http://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html#config-settings-and-precedence
  
I would suggest that you add the credentials in a file like `~/.aws/credentials`, where `~` is the home directory 
of the user who will execute the plugin. This will likely be the nagios user, so then the file will be 
`~nagios/.aws/credentials`.

If you run nagios on an EC2 machine you can also apply a IAM role to the machine with the correct security rights. 

### Installation ###

To make use of this plugin, you should checkout this script in your nagios plugins directory. 

```bash
cd /usr/lib/nagios/plugins/
git clone https://github.com/level23/nagios-cloudwatch-metrics.git
```

Then you should define a command to your nagios configuration. Some example commands:

```
#
# Generic cloudwatch_check
# $ARG1$: Namespace (i.e., ELB, EC2, RDS, etc.)
# $ARG2$: Metric
# $ARG3$: Dimension (i.e., InstanceId)
# $ARG4$: Dimension Value (i.e., i-1a2b3c4d)
# $ARG5$: Warning Level
# $ARG6$: Critical Level
# $ARG7$: Time Interval
# $ARG8$: Default (0 if null)
define command {
       command_name	check_aws
       command_line     $USER1$/nagios-cloudwatch-metrics/check_cloudwatch.sh --region=us-east-1 --namespace="$ARG1$" --metric="$ARG2$" --statistics="Average" --mins=$ARG7$ --dimensions="Name=$ARG3$,Value=$ARG4$" --warning=$ARG5$ --critical=$ARG6$ --default=$ARG8$
}

#
# Check check_aws_firehose
# $ARG1$: Metric, for example: IncomingBytes
# $ARG2$: DeliveryStreamName
# $ARG3$: Warning value
# $ARG4$: Critical value
define command {
	command_name	check_aws_firehose
	command_line	$USER1$/nagios-cloudwatch-metrics/check_cloudwatch.sh --region=eu-west-1 --namespace="Firehose" --metric="$ARG1$" --statistics="Average" --mins=15 --dimensions="Name=DeliveryStreamName,Value=$ARG2$" --warning=$ARG3$ --critical=$ARG4$
}

#
# Check check_aws_lambda
# $ARG1$: Metric, for example: Duration
# $ARG2$: FunctionName
# $ARG3$: Warning value
# $ARG4$: Critical value
define command {
	command_name	check_aws_lambda
	command_line	$USER1$/nagios-cloudwatch-metrics/check_cloudwatch.sh --region=eu-west-1 --namespace="Lambda" --metric="$ARG1$" --statistics="Average" --mins=15 --dimensions="Name=FunctionName,Value=$ARG2$" --warning=$ARG3$ --critical=$ARG4$
}


#
# Check check_aws_sqs
# $ARG1$: Metric, for example: NumberOfMessagesReceived
# $ARG2$: QueueName
# $ARG3$: Warning value
# $ARG4$: Critical value
define command {
	command_name	check_aws_sqs
	command_line	$USER1$/nagios-cloudwatch-metrics/check_cloudwatch.sh --region=eu-west-1 --namespace="SQS" --metric="$ARG1$" --statistics="Sum" --mins=15 --dimensions="Name=QueueName,Value=$ARG2$" --warning=$ARG3$ --critical=$ARG4$
}


#
# Check check_aws_sns
# $ARG1$: Metric, for example: NumberOfNotificationsFailed
# $ARG2$: TopicName
# $ARG3$: Warning value
# $ARG4$: Critical value
define command {
	command_name	check_aws_sns
	command_line	$USER1$/nagios-cloudwatch-metrics/check_cloudwatch.sh --region=eu-west-1 --namespace="SNS" --metric="$ARG1$" --statistics="Sum" --mins=15 --dimensions="Name=TopicName,Value=$ARG2$" --warning=$ARG3$ --critical=$ARG4$
}

#
# Check check_aws_elb
# $ARG1$: Metric, for example: UnHealthyHostCount or HTTPCode_ELB_5XX
# $ARG2$: LoadBalancerName
# $ARG3$: Warning value
# $ARG4$: Critical value
define command {
	command_name	check_aws_elb
	command_line	$USER1$/nagios-cloudwatch-metrics/check_cloudwatch.sh --region=eu-west-1 --namespace="ELB" --metric="$ARG1$" --statistics="Maximum" --mins=1 --dimensions="Name=LoadBalancerName,Value=$ARG2$" --warning=$ARG3$ --critical=$ARG4$
}

#
# Check check_aws_elasticache
# $ARG1$: Metric, for example: CPUUtilization
# $ARG2$: CacheClusterId
# $ARG3$: Warning
# $ARG4$: Critical value
define command {
	command_name	check_aws_elasticache
	command_line	$USER1$/nagios-cloudwatch-metrics/check_cloudwatch.sh --region=eu-west-1 --namespace="ElastiCache" --metric="$ARG1$" --statistics="Average" --mins=15 --dimensions="Name=CacheClusterId,Value=$ARG2$" --warning=$ARG3$ --critical=$ARG4$
}

#
# Check check_aws_cloudfront
# $ARG1$: Metric, for example: 4xxErrorRate
# $ARG2$: DistributionId
# $ARG3$: Warning
# $ARG4$: Critical value
define command {
	command_name	check_aws_cloudfront
	command_line	$USER1$/nagios-cloudwatch-metrics/check_cloudwatch.sh --region=us-east-1 --namespace="CloudFront" --metric="$ARG1$" --statistics="Average" --mins=15 --dimensions="Name=DistributionId,Value=$ARG2$ Name=Region,Value=Global" --warning=$ARG3$ --critical=$ARG4$
}

#
# Check check_aws_rds over last 5 minutes
# $ARG1$: Metric, for example: CPUUtilization
# $ARG2$: ClusterId
# $ARG2$: READER/WRITER
# $ARG3$: Warning
# $ARG4$: Critical value
define command {
	command_name	check_aws_rds
	command_line	$USER1$/nagios-cloudwatch-metrics/check_cloudwatch.sh --region=eu-west-1 --namespace="RDS" --metric="$ARG1$" --statistics="Average" --mins=5 --dimensions="Name=DBClusterIdentifier,Value=$ARG2$ Name=Role,Value=$ARG3$" --warning=$ARG4$ --critical=$ARG5$
}
```

In these examples we have hard-coded defined our region and the X minutes time window. 
 
Then, you can configure your nagios services like this:

```
#
# We assume that there is at least an average of 100 bytes per minute for myStream. If lower, then a warning.
# If lower than 50 Bytes, then it's critical and we should receive an SMS!
#
define service {
        use                         generic-service
        hostgroup_name              cloudwatch
        service_description         Firehose: Incoming Bytes for myStream
        max_check_attempts          2
        normal_check_interval       5
        retry_check_interval        5
        contact_groups              group_sms
        notification_interval       30
        check_command               check_aws_firehose!IncomingBytes!myStream!100!50
}

#
# We assume that myFunction does not run longer than 60000 ms (60s). If so, trigger a warning.
# If it runs longer than 120000 ms (120s), trigger an critical notification.
#
define service {
        use                         generic-service
        hostgroup_name              cloudwatch
        service_description         Lambda: duration of myFunction
        max_check_attempts          2
        normal_check_interval       5
        retry_check_interval        5
        contact_groups              group_sms
        notification_interval       30
        check_command               check_aws_lambda!Duration!myFunction!0:60000!0:120000
}

# etc.
```
