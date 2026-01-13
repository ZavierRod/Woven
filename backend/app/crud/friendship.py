from sqlalchemy.orm import Session
from sqlalchemy import or_, and_
from typing import Optional, List

from app.models.friendship import Friendship, FriendshipStatus
from app.models.user import User


class FriendshipCRUD:
    """CRUD operations for friendships."""

    def send_request(self, db: Session, from_user_id: int, to_user_id: int) -> Friendship:
        """
        Send a friend request from one user to another.

        Should check:
        - Users aren't already friends
        - No pending request already exists (in either direction)
        - User can't friend themselves

        Returns: The created Friendship with status "pending"
        Raises: ValueError if validation fails
        """
        # Can't friend yourself
        if from_user_id == to_user_id:
            raise ValueError("You cannot send a friend request to yourself")

        # Check if friendship already exists (in either direction)
        existing = self.get_existing_friendship(db, from_user_id, to_user_id)
        if existing:
            if existing.status == FriendshipStatus.ACCEPTED.value:
                raise ValueError("You are already friends with this user")
            elif existing.status == FriendshipStatus.PENDING.value:
                raise ValueError(
                    "A friend request already exists between you and this user")

        # Create new friendship request
        friendship = Friendship(
            user_id=from_user_id,
            friend_id=to_user_id,
            status=FriendshipStatus.PENDING.value
        )
        db.add(friendship)
        db.commit()
        db.refresh(friendship)
        return friendship

    def get_pending_requests(self, db: Session, user_id: int) -> List[Friendship]:
        """
        Get all incoming friend requests for a user (requests waiting for their response).

        Returns: List of Friendships where friend_id == user_id and status == "pending"
        """
        return db.query(Friendship).filter(
            Friendship.friend_id == user_id,
            Friendship.status == FriendshipStatus.PENDING.value
        ).all()

    def get_sent_requests(self, db: Session, user_id: int) -> List[Friendship]:
        """
        Get all outgoing friend requests sent by a user.

        Returns: List of Friendships where user_id == user_id and status == "pending"
        """
        return db.query(Friendship).filter(
            Friendship.user_id == user_id,
            Friendship.status == FriendshipStatus.PENDING.value
        ).all()

    def accept_request(self, db: Session, friendship_id: int, user_id: int) -> Optional[Friendship]:
        """
        Accept a pending friend request.

        Should verify:
        - The friendship exists
        - The user is the recipient (friend_id) of the request
        - The status is currently "pending"

        Returns: The updated Friendship with status "accepted", or None if not found/unauthorized
        """
        friendship = self.get_friendship_by_id(db, friendship_id)

        # Check friendship exists
        if not friendship:
            return None

        # Check user is the recipient and status is pending
        if friendship.friend_id != user_id:
            return None
        if friendship.status != FriendshipStatus.PENDING.value:
            return None

        # Accept the request
        friendship.status = FriendshipStatus.ACCEPTED.value
        db.commit()
        db.refresh(friendship)
        return friendship

    def decline_request(self, db: Session, friendship_id: int, user_id: int) -> bool:
        """
        Decline a pending friend request.

        Should verify:
        - The friendship exists
        - The user is the recipient (friend_id) of the request

        Returns: True if declined successfully, False otherwise
        """
        friendship = self.get_friendship_by_id(db, friendship_id)

        # Check friendship exists and user is the recipient
        if not friendship:
            return False
        if friendship.friend_id != user_id:
            return False

        # Delete the request
        db.delete(friendship)
        db.commit()
        return True

    def get_friends(self, db: Session, user_id: int) -> List[User]:
        """
        Get all friends for a user (accepted friendships only).

        Important: User could be either user_id OR friend_id in the friendship record.
        Return the "other" user in each accepted friendship.

        Returns: List of User objects who are friends with this user
        """
        # Get all accepted friendships where user is either user_id or friend_id
        friendships = db.query(Friendship).filter(
            Friendship.status == FriendshipStatus.ACCEPTED.value,
            or_(
                Friendship.user_id == user_id,
                Friendship.friend_id == user_id
            )
        ).all()

        # Extract the "other" user from each friendship
        friends = []
        for f in friendships:
            if f.user_id == user_id:
                # Current user sent the request, so friend is friend_id
                friend = db.query(User).filter(User.id == f.friend_id).first()
            else:
                # Current user received the request, so friend is user_id
                friend = db.query(User).filter(User.id == f.user_id).first()
            if friend:
                friends.append(friend)

        return friends

    def remove_friend(self, db: Session, user_id: int, friend_user_id: int) -> bool:
        """
        Remove an existing friendship between two users.

        Should work regardless of who sent the original request.

        Returns: True if removed successfully, False if friendship didn't exist
        """
        # Find the friendship (in either direction) that is accepted
        friendship = db.query(Friendship).filter(
            Friendship.status == FriendshipStatus.ACCEPTED.value,
            or_(
                and_(Friendship.user_id == user_id,
                     Friendship.friend_id == friend_user_id),
                and_(Friendship.user_id == friend_user_id,
                     Friendship.friend_id == user_id)
            )
        ).first()

        if not friendship:
            return False

        db.delete(friendship)
        db.commit()
        return True

    def are_friends(self, db: Session, user_id_1: int, user_id_2: int) -> bool:
        """
        Check if two users are friends (have an accepted friendship).

        Returns: True if they are friends, False otherwise
        """
        friendship = db.query(Friendship).filter(
            Friendship.status == FriendshipStatus.ACCEPTED.value,
            or_(
                and_(Friendship.user_id == user_id_1,
                     Friendship.friend_id == user_id_2),
                and_(Friendship.user_id == user_id_2,
                     Friendship.friend_id == user_id_1)
            )
        ).first()
        return friendship is not None

    def get_friendship_by_id(self, db: Session, friendship_id: int) -> Optional[Friendship]:
        """
        Get a friendship by its ID.

        Returns: Friendship or None if not found
        """
        return db.query(Friendship).filter(Friendship.id == friendship_id).first()

    def get_existing_friendship(self, db: Session, user_id_1: int, user_id_2: int) -> Optional[Friendship]:
        """
        Check if any friendship exists between two users (any status).

        Useful for checking before sending a new request.

        Returns: Friendship if exists (in either direction), None otherwise
        """
        return db.query(Friendship).filter(
            or_(
                and_(Friendship.user_id == user_id_1,
                     Friendship.friend_id == user_id_2),
                and_(Friendship.user_id == user_id_2,
                     Friendship.friend_id == user_id_1)
            )
        ).first()


# Singleton instance
friendship_crud = FriendshipCRUD()
