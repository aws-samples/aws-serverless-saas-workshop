# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

import json
from aws_lambda_powertools import Metrics

metrics = Metrics()

#TODO: Implement the below method
def record_metric(event, metric_name, metric_unit, metric_value):
    """ Record the metric in Cloudwatch using EMF format

    Args:
        event ([type]): [description]
        metric_name ([type]): [description]
        metric_unit ([type]): [description]
        metric_value ([type]): [description]
    """
    raise NotImplementedError(
        "Learner exercise \u2014 see Solution/Lab3/server/layers/metrics_manager.py"
    )

