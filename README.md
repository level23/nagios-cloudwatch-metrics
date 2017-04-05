# Nagios Cloudwatch Metrics plugin

This plugin allows you to check certain AWS Cloudwatch metrics and set alerts on certain values.
 
The script is written in bash. 

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
                     
```

### Installation ###

To make use of this plugin, you should add the script to your plugins directory. Then you should 
define a command to your nagios configuration. Example commands:

```
#
# Check check_aws_firehose
# $ARG1$: Metric, for example: IncomingBytes
# $ARG2$: DeliveryStreamName
# $ARG3$: Warning value
# $ARG4$: Critical value
define command {
	command_name	check_aws_firehose
	command_line	$USER1$/check_cloudwatch.sh --region=eu-west-1 --namespace="Firehose" --metric="$ARG1$" --statistics="Average" --mins=15 --dimensions="Name=DeliveryStreamName,Value=$ARG2$" --warning=$ARG3$ --critical=$ARG4$
}

#
# Check check_aws_lambda
# $ARG1$: Metric, for example: IncomingBytes
# $ARG2$: DeliveryStreamName
# $ARG3$: Warning value
# $ARG4$: Critical value
define command {
	command_name	check_aws_lambda
	command_line	$USER1$/check_cloudwatch.sh --region=eu-west-1 --namespace="Lambda" --metric="$ARG1$" --statistics="Average" --mins=15 --dimensions="Name=FunctionName,Value=$ARG2$" --warning=$ARG3$ --critical=$ARG4$
}
```

In these examples we have hard-coded defined our region, the 15 minute time window.
 
Then, you can configure your nagios services like this:

```
#
# We assume that there is at least an average of 100 bytes per minute for myStream. If lower, then a warning.
# If lower then 50 Bytes, then its critical and we should receive an SMS!
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
# We assume that myFunction does not run longer then 60000 ms (60s). If so, trigger a warning.
# If it runs longer then 120000 ms (120s), trigger an critical notification.
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
```
