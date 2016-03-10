import argparse
import random

emoj = ['\xf0\x9f\x92\xb8', '\xf0\x9f\x93\xb2', '\xf0\x9f\x90\x96']

parser = argparse.ArgumentParser(description="Annoy a pig and get her to do what I want.")

parser.add_argument('string', type=str, nargs='+')

args = parser.parse_args()

string = args.string[0]

string_arr = string.split(' ')
final_string = ""

while len(string_arr) > 0:

    random_num = random.randrange(0, 3)

    final_string += "{0} ".format(string_arr.pop(0))

    if random_num == 1:
        final_string += "{0}  ".format(random.choice(emoj))


import subprocess
#import pdb;pdb.set_trace()

def write_to_clipboard(output):
    process = subprocess.Popen(
        'pbcopy', env={'LANG': 'en_US.UTF-8'}, stdin=subprocess.PIPE)
    process.communicate(output)# //.encode('unicode_escape'))

print final_string

write_to_clipboard(final_string)
    




