#!/bin/bash
# Claude Code Statusline - Model and Token Usage
# Displays: model name, token usage, and context percentage

# Read JSON input from stdin
input=$(cat)

# Get model display name
model=$(echo "$input" | jq -r '.model.display_name')

# Get token usage information
usage=$(echo "$input" | jq '.context_window.current_usage')

if [ "$usage" != "null" ]; then
    # Calculate current context usage (input + cache creation + cache read)
    input_tokens=$(echo "$usage" | jq '.input_tokens')
    cache_creation=$(echo "$usage" | jq '.cache_creation_input_tokens')
    cache_read=$(echo "$usage" | jq '.cache_read_input_tokens')
    output_tokens=$(echo "$usage" | jq '.output_tokens')

    current_context=$((input_tokens + cache_creation + cache_read))

    # Get context window size
    context_size=$(echo "$input" | jq '.context_window.context_window_size')

    # Calculate percentage
    context_pct=$((current_context * 100 / context_size))

    # Format numbers with K suffix for readability
    format_tokens() {
        local num=$1
        if [ $num -ge 1000 ]; then
            echo "$((num / 1000))K"
        else
            echo "$num"
        fi
    }

    in_formatted=$(format_tokens $current_context)
    out_formatted=$(format_tokens $output_tokens)

    # Output: Model | In/Out tokens | Context %
    echo "${model} | ${in_formatted}/${out_formatted} | ${context_pct}% context"
else
    # No messages yet
    echo "${model} | No messages yet"
fi
