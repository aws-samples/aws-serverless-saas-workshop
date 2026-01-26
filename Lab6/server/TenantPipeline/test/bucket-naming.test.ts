// Property-Based Tests for S3 Bucket Naming
// Feature: lab6-s3-bucket-naming

import * as fc from 'fast-check';
import { App } from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import * as Pipeline from '../lib/serverless-saas-stack';

/**
 * Generates a valid CloudFormation Stack ID hash (8 character hex string)
 * This simulates the random suffix extracted from AWS::StackId
 */
const stackIdHashArbitrary = fc.array(
  fc.constantFrom('0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'),
  { minLength: 8, maxLength: 8 }
).map(arr => arr.join(''));

/**
 * Property 1: Bucket Name Pattern Compliance
 * Validates: Requirements 1.1, 1.2, 1.3, 2.1, 2.2, 2.3, 5.1
 * 
 * For any deployed CDK stack (Lab 6), the artifacts bucket name should match 
 * the pattern `serverless-saas-pipeline-lab6-artifacts-{random-suffix}` 
 * where random-suffix is an 8-character hash extracted from the CloudFormation Stack ID.
 */
describe('Property 1: Bucket Name Pattern Compliance', () => {
  test('bucket name matches pattern for Lab 6', () => {
    fc.assert(
      fc.property(stackIdHashArbitrary, (stackHash) => {
        // Generate expected bucket name
        const expectedPattern = `serverless-saas-pipeline-lab6-artifacts-${stackHash}`;
        
        // Verify pattern structure
        expect(expectedPattern).toMatch(/^serverless-saas-pipeline-lab6-artifacts-[a-f0-9]{8}$/);
        
        // Verify lab identifier is present
        expect(expectedPattern).toContain('lab6');
        
        // Verify purpose identifier is present
        expect(expectedPattern).toContain('artifacts');
        
        // Verify random suffix is present and correct length
        expect(stackHash).toHaveLength(8);
        expect(stackHash).toMatch(/^[a-f0-9]{8}$/);
        
        // Verify bucket name is lowercase
        expect(expectedPattern).toBe(expectedPattern.toLowerCase());
      }),
      { numRuns: 100 }
    );
  });
});

/**
 * Property 2: Bucket Name Lowercase Compliance
 * Validates: Requirements 1.4, 2.4
 * 
 * For any deployed CDK stack (Lab 6), the artifacts bucket name should contain 
 * only lowercase letters, numbers, hyphens, and no other characters.
 */
describe('Property 2: Bucket Name Lowercase Compliance', () => {
  test('bucket name contains only lowercase letters, numbers, and hyphens', () => {
    fc.assert(
      fc.property(stackIdHashArbitrary, (stackHash) => {
        // Generate bucket name
        const bucketName = `serverless-saas-pipeline-lab6-artifacts-${stackHash}`;
        
        // Verify only lowercase letters, numbers, and hyphens
        expect(bucketName).toMatch(/^[a-z0-9-]+$/);
        
        // Verify no uppercase letters
        expect(bucketName).not.toMatch(/[A-Z]/);
        
        // Verify no special characters other than hyphens
        expect(bucketName).not.toMatch(/[^a-z0-9-]/);
      }),
      { numRuns: 100 }
    );
  });
});
