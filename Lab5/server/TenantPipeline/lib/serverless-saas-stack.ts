// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

import { Construct } from 'constructs';
import * as cdk from 'aws-cdk-lib';

import * as s3 from 'aws-cdk-lib/aws-s3';
import * as codecommit from 'aws-cdk-lib/aws-codecommit';
import * as codepipeline from 'aws-cdk-lib/aws-codepipeline';
import * as codepipeline_actions from 'aws-cdk-lib/aws-codepipeline-actions';
import * as codebuild from 'aws-cdk-lib/aws-codebuild';

import { Function, Runtime, AssetCode } from 'aws-cdk-lib/aws-lambda';
import { PolicyStatement } from 'aws-cdk-lib/aws-iam';
import { Duration } from 'aws-cdk-lib';
import * as logs from 'aws-cdk-lib/aws-logs';


export class ServerlessSaaSStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const artifactsBucket = new s3.Bucket(this, "ArtifactsBucket", {
      bucketName: `serverless-saas-pipeline-lab5-artifacts-${cdk.Fn.select(0, cdk.Fn.split('-', cdk.Fn.select(2, cdk.Fn.split('/', cdk.Aws.STACK_ID))))}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
    });

    //Since this lambda is invoking cloudformation which is inturn deploying AWS resources, we are giving overly permissive permissions to this lambda. 
    //You can limit this based upon your use case and AWS Resources you need to deploy.
    const lambdaPolicy = new PolicyStatement()
        lambdaPolicy.addActions("*")
        lambdaPolicy.addResources("*")

    // Create CloudWatch Log Group for Lambda function
    const lambdaLogGroup = new logs.LogGroup(this, 'DeployTenantStackLogGroup', {
      logGroupName: '/aws/lambda/serverless-saas-lab5-deploy-tenant-stack',
      retention: logs.RetentionDays.TWO_MONTHS,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    const lambdaFunction = new Function(this, "deploy-tenant-stack", {
        functionName: 'serverless-saas-lab5-deploy-tenant-stack',
        handler: "lambda-deploy-tenant-stack.lambda_handler",
        runtime: Runtime.PYTHON_3_14,
        code: new AssetCode(`./resources`),
        memorySize: 512,
        timeout: Duration.seconds(10),
        environment: {
            BUCKET: artifactsBucket.bucketName,
        },
        initialPolicy: [lambdaPolicy],
        logGroup: lambdaLogGroup,
    })

    // Pipeline creation starts
    const pipeline = new codepipeline.Pipeline(this, 'Pipeline', {
      pipelineName: 'serverless-saas-pipeline-lab5',
      artifactBucket: artifactsBucket
    });

    // Import existing CodeCommit sam-app repository
    const codeRepo = codecommit.Repository.fromRepositoryName(
      this,
      'AppRepository', 
      'aws-serverless-saas-workshop' 
    );

    // Declare source code as an artifact
    const sourceOutput = new codepipeline.Artifact();

    // Add source stage to pipeline
    pipeline.addStage({
      stageName: 'Source',
      actions: [
        new codepipeline_actions.CodeCommitSourceAction({
          actionName: 'CodeCommit_Source',
          repository: codeRepo,
          branch: 'main',
          output: sourceOutput,
          variablesNamespace: 'SourceVariables'
        }),
      ],
    });

    // Declare build output as artifacts
    const buildOutput = new codepipeline.Artifact();



    //Declare a new CodeBuild project
    const buildProject = new codebuild.PipelineProject(this, 'Build', {
      buildSpec : codebuild.BuildSpec.fromSourceFilename("Lab5/server/tenant-buildspec.yml"),
      environment: { 
        buildImage: codebuild.LinuxBuildImage.STANDARD_7_0,
        privileged: true  // Required for Docker builds in SAM
      },
      environmentVariables: {
        'PACKAGE_BUCKET': {
          value: artifactsBucket.bucketName
        }
      },
      logging: {
        cloudWatch: {
          logGroup: new logs.LogGroup(this, 'BuildLogGroup', {
            logGroupName: '/aws/codebuild/serverless-saas-pipeline-lab5-build',
            retention: logs.RetentionDays.TWO_MONTHS,
            removalPolicy: cdk.RemovalPolicy.DESTROY
          })
        }
      }
    });

    

    // Add the build stage to our pipeline
    pipeline.addStage({
      stageName: 'Build',
      actions: [
        new codepipeline_actions.CodeBuildAction({
          actionName: 'Build-Serverless-SaaS',
          project: buildProject,
          input: sourceOutput,
          outputs: [buildOutput],
        }),
      ],
    });

    const deployOutput = new codepipeline.Artifact();


    //Add the Lambda function that will deploy the tenant stack in a multitenant way
    pipeline.addStage({
      stageName: 'Deploy',
      actions: [
        new codepipeline_actions.LambdaInvokeAction({
          actionName: 'DeployTenantStack',
          lambda: lambdaFunction,
          inputs: [buildOutput],
          outputs: [deployOutput],
          userParameters: {
            'artifact': 'Artifact_Build_Build-Serverless-SaaS',
            'template_file': 'packaged.yaml',
            'commit_id': '#{SourceVariables.CommitId}'
          }
        }),
      ],
    });    
  }
}
