import { Request, Response, NextFunction } from 'express';
import { getAuth } from '@clerk/express';

export function requireApiAuth(
  req: Request,
  res: Response,
  next: NextFunction
): void {
  console.log(true);
  const authState = getAuth(req);
  console.log(authState);

  if (!authState.userId) {
    res.status(401).json({
      error: 'Unauthorized',
    });
    return;
  }

  next();
}
