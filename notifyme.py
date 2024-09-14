#!/usr/bin/env python3

import sys
import time
from pync import Notifier

def main():
    start_time = time.time()  # Record the start time

    end_time = time.time()  # Record the end time
    task_duration = end_time - start_time  # Calculate the duration

    task_description = ' '.join(sys.argv[1:]) if len(sys.argv) > 1 else 'Task completed'

    # Check if the task duration is more than 10 seconds
    if task_duration > 10:
        Notifier.notify(task_description, title='Task Notification', sound='default')

if __name__ == '__main__':
    main()

