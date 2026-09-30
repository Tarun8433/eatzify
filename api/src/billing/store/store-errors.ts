import {
  ConflictException,
  HttpException,
  HttpStatus,
  UnprocessableEntityException,
} from '@nestjs/common';
import {
  PURCHASE_NOT_ACTIVE,
  PURCHASE_OTHER_ACCOUNT,
  STORE_NOT_CONFIGURED,
} from '../billing-copy';

/// The refusals both stores share. `user_message` is the only text the app shows (rule 7).

export function purchaseNotActive(): HttpException {
  return new UnprocessableEntityException({
    status: HttpStatus.UNPROCESSABLE_ENTITY,
    error: { code: 'PURCHASE_NOT_ACTIVE', user_message: PURCHASE_NOT_ACTIVE },
  });
}

export function purchaseOtherAccount(): HttpException {
  return new ConflictException({
    status: HttpStatus.CONFLICT,
    error: {
      code: 'PURCHASE_OTHER_ACCOUNT',
      user_message: PURCHASE_OTHER_ACCOUNT,
    },
  });
}

export function storeNotConfigured(): HttpException {
  return new HttpException(
    {
      status: HttpStatus.SERVICE_UNAVAILABLE,
      error: {
        code: 'STORE_NOT_CONFIGURED',
        user_message: STORE_NOT_CONFIGURED,
      },
    },
    HttpStatus.SERVICE_UNAVAILABLE,
  );
}
