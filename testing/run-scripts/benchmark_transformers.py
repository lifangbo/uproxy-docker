#!/usr/bin/python3

import argparse
import csv
import io
import subprocess
import sys
import time
import urllib.parse

FLOOD_SIZE_MB = 64
FLOOD_MAX_SPEED_MB = 5

parser = argparse.ArgumentParser(
    description='Compare transformer throughput.')
parser.add_argument('clone_path', help='path to pre-built uproxy-lib repo')
args = parser.parse_args()

# Where is flood server?
flood_ip = subprocess.check_output(['./flood.sh', str(FLOOD_SIZE_MB) + 'M',
    str(FLOOD_MAX_SPEED_MB) + 'M'], universal_newlines=True).strip()
print('** using flood server at ' + str(flood_ip))

browser_spec = 'chrome-stable'
tests = {
  'none': ('none', ''),
  'caesar': ('caesar', ''),
  'max. entropy': ('protean', '{ \"encryption\": {\"key\": \"0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0\"}}'),
  'bt': ('header', '{ \"addHeader\": {\"header\": \"41.2\"}, \"removeHeader\": {\"header\": \"41.2\"}}}')
  'both': ('protean', '{ \"encryption\": {\"key\": \"0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0\"}, \"headerInjection\": { \"addHeader\": {\"header\": \"41.2\"}, \"removeHeader\": {\"header\": \"41.2\"}}}'),
}

# Run the benchmarks.
throughput = {}
for test in tests.keys():
  print('** ' + test)

  result = 0
  try:
    # Start the relevant config.
    run_pair = subprocess.Popen(['./run_pair.sh',
        '-p', args.clone_path,
        browser_spec, browser_spec],
        universal_newlines=True,
        stdin=subprocess.PIPE)

    config = tests[test]
    run_pair.stdin.write('transform with ' + config[0] + '\n')
    if config[1]:
      run_pair.stdin.write('transform config ' + config[1] + '\n')
    run_pair.stdin.close()
    run_pair.wait(30)

    # time.time is good for Unix-like systems.
    start = time.time()
    if subprocess.call(['nc', '-X', '5', '-x', 'localhost:9999',
        flood_ip, '1224']) != 0:
      raise Exception('nc failed, proxy probably did not start')
    end = time.time()

    print('** benchmarking...')

    elapsed = round(end - start, 2)
    result = int((FLOOD_SIZE_MB / elapsed) * 1000)

    print('** throughput for ' + test + ': ' + str(result) + 'KB/sec')
  except Exception as e:
    print('** failed to test ' + test + ': ' + str(e))

  throughput[test] = result

# Raw summary.
print('** raw numbers: ' + str(throughput))

# CSV, e.g.:
#   transformer,none,caesar,protean
#   throughput,500,300,100
stringio = io.StringIO()
writer = csv.writer(stringio)
headers = ['test']
headers.extend(tests)
writer.writerow(headers)
figures = ['throughput']
for test in tests:
  figures.append(throughput[test])
writer.writerow(figures)
print('** CSV')
print(stringio.getvalue())

# URL which uses Datacopia's oh-so-simple GET-based API:
print('** http://www.datacopia.com/?data=' + urllib.parse.quote(
    stringio.getvalue()))
