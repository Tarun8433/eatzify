import { Controller, Get, Header, Param } from '@nestjs/common';
import { ApiExcludeController } from '@nestjs/swagger';
import { offerPage } from './offer-page';

/**
 * D-265: `GET /offer/:code` — where a personal-offer link lands in a browser.
 *
 * Public, unversioned and outside the `/api` prefix (`main.ts` excludes it), so the link reads
 * `https://<backend>/offer/<code>`. It touches no database: the page is the same whether the code
 * exists or not, and it only hands the code to the app, which asks the server signed in.
 */
@ApiExcludeController()
@Controller('offer')
export class OfferPageController {
  @Get(':code')
  @Header('Content-Type', 'text/html; charset=utf-8')
  @Header('Cache-Control', 'no-store')
  @Header('Referrer-Policy', 'no-referrer')
  page(@Param('code') code: string): string {
    return offerPage(code);
  }
}
