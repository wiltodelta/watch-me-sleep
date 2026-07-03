#!/bin/bash

# Build the app if not already built or if source files changed
if [ ! -f ".build/release/WatchMeSleep" ] || [ Sources -nt .build/release/WatchMeSleep ]; then
    echo "Building Watch Me While I Fall Asleep..."
    swift build -c release
    if [ $? -ne 0 ]; then
        echo "Build failed!"
        exit 1
    fi
fi

# Run the application
echo "Starting Watch Me While I Fall Asleep..."
.build/release/WatchMeSleep
