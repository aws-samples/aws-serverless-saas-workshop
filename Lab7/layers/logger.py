# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

from aws_lambda_powertools import Logger
logger = Logger()

def info(log_message):
    """Log info messages"""
    logger.info(log_message)

def error(log_message):
    """Log error messages"""
    logger.error(log_message)

def log_with_tenant_context(tenant_id, log_message, **kwargs):
    """Log with tenant context and additional structured data"""
    logger.structure_logs(append=True, tenant_id=tenant_id)
    if kwargs:
        logger.info(log_message, extra=kwargs)
    else:
        logger.info(log_message)
