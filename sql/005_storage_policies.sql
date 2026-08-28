-- sql/005_storage_policies.sql
-- Storage policies (Bucket is eco-imports-private-staging, private)

-- Assumes bucket exists with id = 'eco-imports-private-staging'

CREATE POLICY "Allow org to select its files"
ON storage.objects
FOR SELECT
TO authenticated
USING (
    bucket_id = 'eco-imports-private-staging'
    AND (storage.foldername(name))[1] = private.org_id()::text
);

CREATE POLICY "Allow org to insert its files"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'eco-imports-private-staging'
    AND (storage.foldername(name))[1] = private.org_id()::text
);

CREATE POLICY "Allow org to delete its files"
ON storage.objects
FOR DELETE
TO authenticated
USING (
    bucket_id = 'eco-imports-private-staging'
    AND (storage.foldername(name))[1] = private.org_id()::text
);
