#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { ServerlessSaaSStack } from '../lib/serverless-saas-stack';

const app = new cdk.App();
new ServerlessSaaSStack(app, 'serverless-saas-pipeline');
