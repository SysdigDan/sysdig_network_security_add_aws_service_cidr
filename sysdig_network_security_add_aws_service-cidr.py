# Make sure to have 2 environment variables set
# export API_TOKEN="<Your Sysdig Secure API Token>""
# export API_ENDPOINT="https://app.au1.sysdig.com"

import requests
import os
import json
import argparse

API_TOKEN = os.getenv('API_TOKEN')
API_ENDPOINT = os.getenv('API_ENDPOINT')
API_HEADERS = {
  'Authorization': 'Bearer ' + API_TOKEN,
  'Content-Type': 'application/json'
}

def opts():
    parser = argparse.ArgumentParser()

    parser.add_argument("-a", "--aws_service",
                        help="AWS Service (ex: -a 'S3')")

    parser.add_argument("-r", "--aws_region",
                        help="AWS Region (ex: -r 'us-east-1')")

    args = parser.parse_args()

    if args.aws_service and not args.aws_region:
        parser.error('AWS Service and Region are required.')

    return {
        'AWS_SERVICE':args.aws_service,
        'AWS_REGION':args.aws_region
    }

def get_aws_cidr_ranges(aws_service, aws_region) :
    # aws source url
    aws_cidr_ranges = requests.get('https://ip-ranges.amazonaws.com/ip-ranges.json').json()['prefixes']
    service_cidr = [item['ip_prefix'] for item in aws_cidr_ranges if item["service"] == aws_service and item["region"] == aws_region]

    # define new unresolvedIP configuraiton template
    unresolved_ip_template = {
        "ipsOrCIDRs": service_cidr,
        "alias": aws_service.upper() + '-' + aws_region.upper(),
        "allowedByDefault": True
    }

    return unresolved_ip_template

def get_sysdig_config(aws_service, aws_region) :
    url = API_ENDPOINT + '/api/v1/networkTopology/customerConfig'
    print('Checking current configuration ...')
    sysdig_configuration = requests.request("GET", url, headers=API_HEADERS)

    if sysdig_configuration.json()['unresolvedIPs'] is not None:
        unresolved_cidr_ips = sysdig_configuration.json()['unresolvedIPs']
        print('Checking if alias '+ aws_service.upper() + '-' + aws_region.upper() +' exists ...')
        for group in unresolved_cidr_ips:
            print('Cross checking existing alias ' + group['alias'] + '...')
            if group['alias'] == aws_service.upper() + '-' + aws_region.upper():
                print('Found existing alias.')
                quit()
    else:
        print('No Results.')
        quit()

    return sysdig_configuration.json()

def set_sysdig_config(current_config, new_cidr_group) :
    url = API_ENDPOINT + '/api/v1/networkTopology/customerConfig'

    print('Setting new configuration ...')

    # convert dict to string
    current_config = json.dumps(current_config)
    # convert it to a python dictionary
    current_config = json.loads(current_config)
    # append your data as {key:value}
    current_config['unresolvedIPs'].append(new_cidr_group)
    # convert it back to string
    payload = json.dumps(current_config)

    print(payload)

    response = requests.request("PUT", url, headers=API_HEADERS, data=payload)
    return response.json()

def main():
    args = opts()

    current_config = get_sysdig_config(args['AWS_SERVICE'], args['AWS_REGION'])
    new_cidr_group = get_aws_cidr_ranges(args['AWS_SERVICE'], args['AWS_REGION'])

    response = set_sysdig_config(current_config, new_cidr_group)

    # Output JSON Results to terminal
    print(json.dumps(response,indent=4, sort_keys=False))

if __name__ == '__main__':
    main()
