from copilot.session import PostToolUseHookInput, PostToolUseHookOutput
from typing import Callable, Awaitable
import json
from pprint import pformat
import sys
from subprocess import Popen, run
import pathlib
import logging

logger = logging.getLogger(__name__)
logging.basicConfig(filename='logs/create.log', encoding='utf-8', level=logging.DEBUG)

payload_str = input()
payload = json.loads(payload_str)
print(payload_str, file=open('logs/payload.json', 'w'))

logger.info(f"Processing payload: {pformat(payload)}")

if payload['tool_name'] == 'create_file' or payload['tool_name'] == 'modify_file':
    suffix = pathlib.Path(payload['tool_input']['filePath']).suffix
    if suffix in ['.c', '.cpp', '.h', '.hpp']:
        logger.info(f"Running clang-format on {payload['tool_input']['content']}")

        lc = ["clang-format"]
        clang_process = run(lc, input=payload['tool_input']['content'], text=True, capture_output=True)
        logger.info(f"clang-format output: {clang_process.stdout}")

        # print clean c-lang formatted code to stdout, which will be used as the content for the file created/modified by the create_file/modify_file tool
        response = {
            "modifiedArgs": 
                (payload['tool_input']
                 | {
                    'content': clang_process.stdout
                }),
            "additionalContext": 'c-lang formatted code'
        }
        json_data = json.dumps(response)
        logger.info(f"Returning response: {pformat(json_data)}")
        print(json_data, file=open('logs/response.json', 'w'))
        print(json_data)
        sys.exit(clang_process.returncode)
else:
    logger.info(f"Unknown tool name: {payload['tool_name']}")
