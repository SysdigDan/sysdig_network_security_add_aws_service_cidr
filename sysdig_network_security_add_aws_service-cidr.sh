#!/bin/bash
source include_config

# Sysdig
SYSDIG_SECURE_ENDPOINT=""
SYSDIG_SECURE_AUTH_TOKEN=""
# AWS
AWS_IP_RANGES_URL=https://ip-ranges.amazonaws.com/ip-ranges.json
AWS_SERVICE=""
AWS_REGION=""

usage () {
  cat >&2 << EOF

Add AWS Service CIDR to Sysdig Network Security Unresolved IP Configuration -- USAGE

Usage: ${0##*/} -s <sysdig_url> -k xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx -a <aws_service> -r <aws_region>

  == OPTIONS ==

  -s <URL>    [required] Sysdig Secure URL
                  (ex: -s 'secure-sysdig.svc.cluster.local')
                  If not specified, it will default to Sysdig Secure SaaS URL (https://secure.sysdig.com)
  -k <TEXT>   [required] API token for Sysdig Scanning auth
                  (ex: -k 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx')
  -a <TEXT>    [required] AWS Service
                  (ex: -a 'S3')
                  Other options include -
  -r <TEXT>    [required] AWS Region
                  (ex: -r 'us-east-1')
                  Other options include -

EOF
}

main() {
  get_options "$@"

  get_aws_ranges
  check_sysdig_config
  set_sysdig_config

  echo "Done"

}

get_options() {
  while getopts "s:k:a:r:?h:" option; do
    case "${option}" in
      s) s_flag=true; SYSDIG_SECURE_ENDPOINT=${OPTARG} ;;
      k) k_flag=true; SYSDIG_SECURE_AUTH_TOKEN=${OPTARG} ;;
      a) a_flag=true; AWS_SERVICE=${OPTARG} ;;
      r) r_flag=true; AWS_REGION=${OPTARG} ;;
      h|?) usage; exit ;;
    esac
  done

  if [[ -z $SYSDIG_SECURE_ENDPOINT ]]; then
    printf "ERROR: must specify Sysdig url - %s without trailing slash\n\n" >&2
    usage
    exit 2;
  elif [[ -z $SYSDIG_SECURE_AUTH_TOKEN ]]; then
    printf "ERROR: must provide the Sysdig Secure API token\n\n" >&2
    usage
    exit 2;
  elif [[ -z $AWS_SERVICE ]]; then
    printf "ERROR: must provide the AWS Service\n\n" >&2
    usage
    exit 2;
  elif [[ -z $AWS_REGION ]]; then
    printf "ERROR: must provide the AWS Region\n\n" >&2
    usage
    exit 2;
  fi
}

get_aws_ranges() {
  # Define new UnresolvedIP Configuraiton
  unresolvedIP='{"ipsOrCIDRs":[],"alias":"'${AWS_SERVICE^^}-${AWS_REGION^^}'","allowedByDefault":true}'

  # Get list of AWS Service IP Ranges
  awsRanges=$(
    curl -s -k --location --request GET "${AWS_IP_RANGES_URL}" \
    | jq -r '.prefixes[] | select(.service=="'${AWS_SERVICE}'") | select(.region=="'${AWS_REGION}'")' | jq -s '.'
  )

  # Check if alias already exists
  if [[ $awsRanges ]]; then
    echo "Error: No AWS CIDR for AWS ${AWS_SERVICE} are available."
    exit
  fi

  # For each AWS IP Range that matches define service and region add to list
  for i in $(jq -s '.[] | keys | .[]' <<< "$awsRanges"); do
    j=$(jq -r ".[$i]" <<< "$awsRanges");
    cidr=$(jq -r ".ip_prefix" <<< "$j");

    # Add new CIDR to Configuration
    unresolvedIP=$(echo $unresolvedIP | jq -r '.ipsOrCIDRs += ["'$cidr'"]')
  done
}

check_sysdig_config() {
  currentConfig=$(
    curl -s -k --location --request GET "https://${SYSDIG_SECURE_ENDPOINT}/api/v1/networkTopology/customerConfig" \
    --header "Content-Type: application/json;charset=UTF-8" \
    --header "X-Sysdig-Product: SDC" \
    --header "Authorization: Bearer ${SYSDIG_SECURE_AUTH_TOKEN}"
  )

  # Check if alias already exists
  if [[ $(jq '.unresolvedIPs[]? | select(.alias == "'${AWS_SERVICE^^}-${AWS_REGION^^}'")' <<< $currentConfig) ]]; then
    echo "Unresolved IP Configuration '${AWS_SERVICE^^}-${AWS_REGION^^}' already exists. Delete manually before trying again."
    exit
  fi
}

set_sysdig_config() {
  # Create new Network Security Configuration from Sysdig
  customerConfig=$(echo $currentConfig | jq -r ".unresolvedIPs += [$unresolvedIP]")

  # Apply new configuration
  curl -s -k --location --request PUT "https://$SYSDIG_SECURE_ENDPOINT/api/v1/networkTopology/customerConfig" \
  --header "Content-Type: application/json;charset=UTF-8" \
  --header "X-Sysdig-Product: SDC" \
  --header "Authorization: Bearer $SYSDIG_SECURE_AUTH_TOKEN" \
  --data-raw "$customerConfig" \
  | jq .
}

main "$@"
