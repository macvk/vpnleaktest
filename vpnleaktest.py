#!/usr/bin/env python3
# encoding=utf-8
# VPN connection test client for bash.ws.
# Project: https://github.com/macvk/vpnleaktest
# SPDX-License-Identifier: MIT

import argparse
import datetime
import ipaddress
import json
import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from platform import system as system_name

try:
    from urllib.error import HTTPError, URLError
    from urllib.parse import urlencode, urlparse
    from urllib.request import Request, urlopen
except ImportError:
    from urllib2 import HTTPError, Request, URLError, urlopen
    from urllib import urlencode
    from urlparse import urlparse


VERSION = '1.0.0'
API_DOMAIN = 'bash.ws'
DEFAULT_API = 'https://' + API_DOMAIN


def bounded_integer(minimum, maximum, description):
    def convert(value):
        try:
            number = int(value)
        except ValueError:
            raise argparse.ArgumentTypeError(description)

        if number < minimum or (maximum is not None and number > maximum):
            raise argparse.ArgumentTypeError(description)

        return number
    return convert


def parse_args():
    parser = argparse.ArgumentParser(description='Check a VPN connection for IP, DNS, port, and blacklist risks.')
    parser.add_argument('-i', '--interface', metavar='NAME|IP', help='use a specific network interface (requires curl)')
    parser.add_argument('-p', '--probes', metavar='NUMBER', type=bounded_integer(1, 100, 'must be an integer from 1 to 100'), default=30, help='number of DNS probes to send (default: 30)')
    parser.add_argument('-j', '--parallel', metavar='NUMBER', type=bounded_integer(1, 100, 'must be an integer from 1 to 100'), default=30, help='maximum simultaneous DNS probes (default: 30)')
    parser.add_argument('-t', '--timeout', metavar='SECONDS', type=bounded_integer(10, 300, 'must be an integer from 10 to 300'), default=90, help='maximum time for each test (default: 90)')
    parser.add_argument('-s', '--short', action='store_true', help='print a one-line result')
    parser.add_argument('-w', '--watch', metavar='SECONDS', nargs='?', const=0, type=bounded_integer(0, None, 'must be zero or a positive integer'), help='repeat continuously in short mode (default interval: 0)')
    parser.add_argument('--json', action='store_true', help='print structured JSON')
    parser.add_argument('--api-base', default=DEFAULT_API, help=argparse.SUPPRESS)
    parser.add_argument('--version', action='version', version=VERSION)
    return parser.parse_args()


class BashwsClient(object):
    def __init__(self, api_base, interface, timeout):
        self.api_base = api_base.rstrip('/')
        self.interface = interface
        self.timeout = timeout
        parsed = urlparse(self.api_base)
        host = parsed.hostname or API_DOMAIN
        self.probe_domain = host
        self.probe_scheme = parsed.scheme or 'https'

        if host == API_DOMAIN or host.endswith('.' + API_DOMAIN):
            self.probe_domain = API_DOMAIN
            self.probe_scheme = 'https'

    def request(self, url, fields=None):
        if not url.startswith('http://') and not url.startswith('https://'):
            url = self.api_base + (url if url.startswith('/') else '/' + url)

        encoded = urlencode(fields, doseq=True).encode('ascii') if fields is not None else None

        if self.interface:
            command = ['curl', '--silent', '--show-error', '--fail', '--max-time', str(self.timeout), '--interface', self.interface]

            if encoded is not None:
                command.extend(['--data', encoded.decode('ascii')])

            command.append(url)
            process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            output, error = process.communicate()

            if process.returncode:
                raise RuntimeError(error.decode('utf-8', errors='replace').strip())

            return output.decode('utf-8').strip()

        request = Request(url, data=encoded, headers={'User-Agent': 'bash.ws vpnleaktest/' + VERSION})
        response = urlopen(request, timeout=self.timeout)
        return response.read().decode('utf-8').strip()

    def json_request(self, path, fields=None):
        content = self.request(path, fields)

        try:
            response = json.loads(content)
        except ValueError:
            raise RuntimeError('Invalid response from {}: {}'.format(path, content[:160] or '[empty response]'))

        return response

    def test_id(self):
        value = self.request('/id').strip().lower()

        if len(value) != 16 or not value.isalnum():
            raise RuntimeError('Invalid test ID returned by /id')

        return value


def ping_command(host, interface):
    current_system = system_name().lower()

    if current_system == 'windows':
        command = ['ping', '-n', '1', '-w', '1000', host]

        if interface:
            command[1:1] = ['-S', interface]
    elif current_system == 'darwin':
        command = ['ping', '-c', '1', '-W', '1000', host]

        if interface:
            command[1:1] = ['-S' if (':' in interface or interface.replace('.', '').isdigit()) else '-b', interface]
    else:
        command = ['ping', '-c', '1', '-W', '1', host]

        if interface:
            command[1:1] = ['-I', interface]

    return command


def send_dns_probe(host, interface):
    with open(os.devnull, 'wb') as devnull:
        return subprocess.call(ping_command(host, interface), stdout=devnull, stderr=devnull) == 0


def run_dns_test(client, test_id, probes, parallel, interface):
    with ThreadPoolExecutor(max_workers=min(probes, parallel)) as executor:
        futures = [executor.submit(send_dns_probe, '{}.{}.{}'.format(index, test_id, client.probe_domain), interface) for index in range(1, probes + 1)]

        for future in futures:
            future.result()

    time.sleep(1.5)
    return run_test(client, test_id, '/dnsleak', query='json=2')


def run_test(client, test_id, route, fields=None, suffix='', query='json'):
    response = client.json_request('{}/test/{}{}?{}'.format(route, test_id, suffix, query), fields)

    if not isinstance(response, list):
        raise RuntimeError('Invalid response from {} test'.format(route))

    for record in response:
        if isinstance(record, dict) and record.get('type') == 'error':
            raise RuntimeError(record.get('text') or '{} test failed'.format(route))

    return response


def start_test(client, test_id, route, suffix=''):
    path = '{}/test/{}{}'.format(route, test_id, suffix)
    response = client.json_request(path, {})

    if not isinstance(response, dict):
        raise RuntimeError('Invalid response while starting {} test'.format(route))

    if response.get('error') or not response.get('done'):
        raise RuntimeError(response['error'])


def detect_address(client, family, test_id):
    url = '{}://{}.{}/myip/test/{}'.format(client.probe_scheme, family, client.probe_domain, test_id)

    try:
        value = client.request(url).strip()
        address = ipaddress.ip_address(value)
        expected_version = 4 if family == 'ipv4' else 6
        return value if address.version == expected_version else ''
    except (HTTPError, URLError, RuntimeError, ValueError, OSError):
        return ''


def final_result(client, test_id, text_output=False):
    if text_output:
        return client.request('/vpn-leak-test/test/{}?txt'.format(test_id))

    response = client.json_request('/vpn-leak-test/test/{}?json'.format(test_id))

    if not isinstance(response, list):
        raise RuntimeError('Invalid response from VPN connection check')

    for record in response:
        if isinstance(record, dict) and record.get('type') == 'error':
            raise RuntimeError(record.get('text') or 'VPN connection check failed')

    return response


def run(args):
    if args.interface:
        try:
            subprocess.check_call(['curl', '--version'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        except (OSError, subprocess.CalledProcessError):
            raise SystemExit('curl is required when --interface is used')

    started = time.monotonic()
    client = BashwsClient(args.api_base, args.interface, args.timeout)

    try:
        test_id = client.test_id()

        with ThreadPoolExecutor(max_workers=2) as executor:
            futures = {family: executor.submit(detect_address, client, family, test_id) for family in ('ipv4', 'ipv6')}
            addresses = {family: future.result() for family, future in futures.items()}

        run_dns_test(client, test_id, args.probes, args.parallel, args.interface)
        start_test(client, test_id, '/open-port-check')
        run_test(client, test_id, '/open-port-check')

        for family in ('ipv4', 'ipv6'):
            if addresses[family]:
                suffix = '/{}'.format(family)
                start_test(client, test_id, '/ip-blacklist-check', suffix)
                run_test(client, test_id, '/ip-blacklist-check', suffix=suffix)

        text_output = not args.json and not args.short
        result = final_result(client, test_id, text_output)
    except (HTTPError, URLError, RuntimeError, ValueError, OSError) as error:
        raise SystemExit('VPN connection check failed: {}'.format(error))

    if text_output:
        print(result, end='' if result.endswith('\n') else '\n')
        return 0

    conclusion = ''

    for record in result:
        kind = record.get('type', '')

        if kind == 'conclusion':
            conclusion = record.get('text', '')

    if not conclusion:
        raise RuntimeError('Invalid conclusion returned by VPN connection check')

    elapsed = time.monotonic() - started
    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    elif args.short:
        timestamp = datetime.datetime.now().astimezone().isoformat(timespec='seconds')
        print('{} {:.2f}s {}'.format(timestamp, elapsed, conclusion))

    return 0


def main():
    args = parse_args()

    if args.watch is not None:
        args.short = True
        args.json = False

    while True:
        status = run(args)

        if args.watch is None:
            return status

        if args.watch:
            time.sleep(args.watch)


if __name__ == '__main__':
    sys.exit(main())
