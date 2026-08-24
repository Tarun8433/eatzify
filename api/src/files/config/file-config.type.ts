export enum FileDriver {
  LOCAL = 'local',
  S3 = 's3',
  S3_PRESIGNED = 's3-presigned',
}

export type FileConfig = {
  driver: FileDriver;
  accessKeyId?: string;
  secretAccessKey?: string;
  awsDefaultS3Bucket?: string;
  awsS3Region?: string;
  /** S3-compatible endpoint. Set for Cloudflare R2; leave unset for real AWS S3. */
  s3Endpoint?: string;
  /** R2 and most S3-compatible stores need path-style addressing. */
  s3ForcePathStyle: boolean;
  maxFileSize: number;
};
