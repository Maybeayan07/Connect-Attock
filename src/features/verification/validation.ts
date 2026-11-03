export const verificationMimeTypes = ['image/jpeg', 'image/png', 'image/webp', 'application/pdf'] as const
export const maxVerificationFileBytes = 10 * 1024 * 1024
export function validateVerificationFile(file: Pick<File, 'type' | 'size'>) { if (!verificationMimeTypes.includes(file.type as typeof verificationMimeTypes[number])) return 'Use JPG, PNG, WEBP or PDF files only.'; if (file.size < 1 || file.size > maxVerificationFileBytes) return 'Each verification file must be 10 MB or smaller.'; return null }
export function hasRequiredVerificationDocuments(types: string[]) { return ['identity', 'driving_licence', 'vehicle_registration', 'vehicle_image'].every((required) => types.includes(required)) }
